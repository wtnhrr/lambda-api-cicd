# Lambda API — CI/CD com GitHub Actions + AWS

Pipeline completo de CI/CD que faz deploy automático de uma API Python no AWS Lambda via container Docker. A cada `git push` na branch `main`, o GitHub Actions constrói a imagem, publica no ECR e atualiza a Lambda automaticamente.

## Arquitetura

```
Git push → GitHub Actions
               │
               ├── Build imagem Docker
               ├── Push para ECR (registro privado AWS)
               └── Update Lambda → API Gateway → Internet
```

```
Internet → API Gateway (HTTP API)
                │
                └── Lambda Function (container Python)
                        └── ECR (imagem Docker)
```

## Endpoints

| Método | Path | Descrição |
|--------|------|-----------|
| GET | `/` | Informações da API e rotas disponíveis |
| GET | `/health` | Health check com timestamp |
| GET | `/info` | Metadados da função Lambda em execução |

## Stack

- **Runtime**: Python 3.12 (container Lambda)
- **Infra**: Terraform (ECR + Lambda + API Gateway + IAM)
- **CI/CD**: GitHub Actions
- **Registry**: Amazon ECR
- **Compute**: AWS Lambda (serverless)
- **Gateway**: Amazon API Gateway HTTP API

## Custo estimado

| Serviço | Free Tier | Custo após |
|---------|-----------|------------|
| Lambda | 1M invocações/mês — para sempre | US$ 0,20 / 1M req |
| API Gateway | 1M req/mês por 12 meses | US$ 1,00 / 1M req |
| ECR | 500 MB/mês por 12 meses | US$ 0,10 / GB |

**Custo real para portfólio: $0,00**

## Como rodar

> **Nota:** este projeto foi desenvolvido e testado em **Windows 11 + Docker Desktop**. Os comandos abaixo já refletem os ajustes necessários para esse ambiente.

### Pré-requisitos

- AWS CLI configurado (`aws configure`)
- Terraform >= 1.3.0
- Docker Desktop (com o motor Linux containers ativo)
- Conta GitHub
- PowerShell (padrão no Windows 11)

### 1. Clone e configure

```
git clone https://github.com/wtnhrr/lambda-api-cicd.git
cd lambda-api-cicd
```

### 2. Provisione a infraestrutura com Terraform

```
cd terraform
terraform init
terraform apply
```

Anote o `ecr_repository_url` do output — você vai precisar dele no próximo passo.

> **Por quê o `apply` pode falhar na primeira vez:** o Terraform tenta criar a Lambda apontando para uma imagem `:latest` no ECR, mas essa imagem ainda não existe nesse ponto. É esperado ver o erro `Source image does not exist`. Continue para o passo 3 e depois rode `terraform apply` novamente — dessa vez a imagem já vai existir no ECR.

### 3. Faça o primeiro deploy manual da imagem

A Lambda precisa de uma imagem real no ECR antes de funcionar.

**Login no ECR:**

```
$token = aws ecr get-login-password --region us-east-1
docker login --username AWS --password $token ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com
```

> **Observação Windows:** a documentação oficial da AWS sugere `aws ecr get-login-password | docker login --password-stdin`. Esse pipe não funciona no PowerShell (retorna `400 Bad Request`). A solução é separar em duas linhas como acima, guardando o token numa variável.

Para descobrir seu `ACCOUNT_ID`:
```
aws sts get-caller-identity --query Account --output text
```

**Build e push da imagem:**

```
docker build --platform linux/amd64 --provenance=false -t SEU_ECR_REPOSITORY_URL:latest .
docker push SEU_ECR_REPOSITORY_URL:latest
```

> **Observação Windows/Docker Desktop:** as flags `--platform linux/amd64 --provenance=false` são obrigatórias. Sem `--provenance=false`, o Docker Desktop moderno gera a imagem no formato OCI, que o AWS Lambda não suporta — resulta no erro `image manifest, config or layer media type ... is not supported`.

**Atualize a Lambda com a imagem:**

```
aws lambda update-function-code --function-name user-lambda-api --image-uri SEU_ECR_REPOSITORY_URL:latest
```

### 4. Rode o Terraform apply novamente

```
terraform apply
```

Agora a Lambda e o API Gateway são criados com sucesso, já que a imagem existe no ECR.

### 5. Configure os Secrets no GitHub

Vá em: **Settings > Secrets and variables > Actions > New repository secret**

| Secret | Valor |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | Access Key de um usuário IAM dedicado ao CI/CD |
| `AWS_SECRET_ACCESS_KEY` | Secret Key desse mesmo usuário |

> **Boa prática:** crie um usuário IAM separado (ex: `github-actions-cicd`) só para o pipeline, com permissões mínimas (`AmazonEC2ContainerRegistryPowerUser` + `AWSLambda_FullAccess`). Nunca use as credenciais do seu usuário principal nos Secrets do GitHub.

### 6. Teste o pipeline

```
git add .
git commit -m "feat: trigger CI/CD pipeline"
git push origin main
```

Acompanhe em: **GitHub > Actions**

> **Sobre o aviso de Node.js 20 deprecated:** se aparecer esse warning no pipeline, atualize as versions das actions no `deploy.yml` para `aws-actions/configure-aws-credentials@v6.1.0` e `aws-actions/amazon-ecr-login@v2.0.1` (ou versões mais recentes), que já suportam Node.js 24.

### 7. Teste a API

```
curl https://SEU_API_ID.execute-api.us-east-1.amazonaws.com/
curl https://SEU_API_ID.execute-api.us-east-1.amazonaws.com/health
curl https://SEU_API_ID.execute-api.us-east-1.amazonaws.com/info
```

### 8. Destruindo o ambiente (importante para não gerar custo)

```
cd terraform
terraform destroy
```

> **Observação:** se o `destroy` falhar com `RepositoryNotEmptyException`, é porque o ECR ainda tem imagens e por padrão o Terraform não deleta repositórios não vazios — comportamento correto para evitar perda acidental de imagens em produção. Para ambiente de dev/portfólio, defina `force_delete_ecr = true` no `terraform.tfvars` antes de rodar `apply` seguido de `destroy`. Veja a variável `force_delete_ecr` em `variables.tf`.

## Estrutura do projeto

```
lambda-api-cicd/
├── .github/
│   └── workflows/
│       └── deploy.yml        # Pipeline CI/CD completo
├── app/
│   └── handler.py            # Código da Lambda (roteamento + handlers)
├── terraform/
│   ├── main.tf               # ECR, Lambda, API Gateway, IAM
│   ├── variables.tf          # Variáveis configuráveis
│   └── outputs.tf            # URL da API, ECR URL, etc
├── Dockerfile                # Imagem container para Lambda
├── .gitignore
└── README.md
```

## Decisões de design

- **`lifecycle { ignore_changes = [image_uri] }`**: o Terraform cria a infraestrutura, o CI/CD cuida dos deploys. Sem isso, um `terraform apply` reverteria os deploys do pipeline.
- **`force_delete_ecr` como variável booleana**: `false` por padrão (protege imagens em produção contra deleção acidental), `true` em dev/portfólio para permitir limpeza completa do ambiente.
- **Secrets no GitHub, nunca no código**: credenciais AWS ficam em `Settings > Secrets`, injetadas como variáveis de ambiente apenas durante a execução do pipeline, usando um usuário IAM dedicado com permissões mínimas.
- **Smoke test no pipeline**: após o deploy, o pipeline testa o endpoint `/health`. Se falhar, você é notificado antes de qualquer usuário perceber.
- **ECR lifecycle policy**: mantém apenas as últimas 5 imagens para evitar custo de armazenamento desnecessário.
- **`--provenance=false` no build**: necessário para compatibilidade do formato de imagem com o AWS Lambda, que não suporta o formato OCI gerado por padrão pelo Docker Desktop moderno.

## Problemas reais resolvidos durante o desenvolvimento

| Problema | Causa | Solução |
|---|---|---|
| `image manifest ... is not supported` | Docker Desktop gera imagens em formato OCI, Lambda só aceita Docker v2 | `--provenance=false` no build |
| `RepositoryNotEmptyException` no destroy | ECR protege repositórios com imagens por padrão | Variável `force_delete_ecr` |
| Aviso de Node.js 20 deprecated | GitHub forçando migração para Node.js 24 nas Actions | Atualizar para versões mais recentes das actions da AWS |

## Tecnologias

![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-CI%2FCD-2088FF?logo=githubactions)
![AWS Lambda](https://img.shields.io/badge/AWS-Lambda-FF9900?logo=awslambda)
![Docker](https://img.shields.io/badge/Docker-Container-2496ED?logo=docker)
![Terraform](https://img.shields.io/badge/Terraform-IaC-623CE4?logo=terraform)
![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python)