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

### Pré-requisitos

- AWS CLI configurado (`aws configure`)
- Terraform >= 1.3.0
- Docker
- Conta GitHub

### 1. Clone e configure

```bash
git clone https://github.com/wtnhrr/lambda-api-cicd.git
cd lambda-api-cicd
```

### 2. Provisione a infraestrutura com Terraform

```bash
cd terraform
terraform init
terraform apply
```

Anote o `ecr_repository_url` do output — você vai precisar dele.

### 3. Faça o primeiro deploy manual da imagem

A Lambda precisa de uma imagem no ECR antes de funcionar.

```bash
# Autentique o Docker no ECR (substitua ACCOUNT_ID e REGION)
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Build e push da imagem
IMAGE_URI="SEU_ECR_REPOSITORY_URL:latest"
docker build -t "$IMAGE_URI" .
docker push "$IMAGE_URI"

# Atualize a Lambda com a imagem
aws lambda update-function-code \
  --function-name user-lambda-api \
  --image-uri "$IMAGE_URI"
```

### 4. Configure os Secrets no GitHub

Vá em: **Settings > Secrets and variables > Actions > New repository secret**

| Secret | Valor |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | Sua AWS Access Key |
| `AWS_SECRET_ACCESS_KEY` | Sua AWS Secret Key |

### 5. Teste o pipeline

```bash
git add .
git commit -m "feat: trigger CI/CD pipeline"
git push origin main
```

Acompanhe em: **GitHub > Actions**

### 6. Teste a API

```bash
# Substitua pela URL do output do Terraform
curl https://SEU_API_ID.execute-api.us-east-1.amazonaws.com/health
```

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

- **Container em vez de zip**: permite dependências maiores, ambiente reproduzível e scan de vulnerabilidades automático no ECR.
- **`lifecycle { ignore_changes = [image_uri] }`**: o Terraform cria a infraestrutura, o CI/CD cuida dos deploys. Sem isso, um `terraform apply` reverteria os deploys do pipeline.
- **Secrets no GitHub, nunca no código**: credenciais AWS ficam em `Settings > Secrets`, injetadas como variáveis de ambiente apenas durante a execução do pipeline.
- **Smoke test no pipeline**: após o deploy, o pipeline testa o endpoint `/health`. Se falhar, você é notificado antes de qualquer usuário perceber.
- **ECR lifecycle policy**: mantém apenas as últimas 5 imagens para evitar custo de armazenamento desnecessário.

## Próximos passos

- [ ] Adicionar testes unitários com `pytest` rodando antes do deploy
- [ ] Criar ambiente de staging (branch `develop` → Lambda de staging)
- [ ] Adicionar notificação no Slack quando o deploy falhar
- [ ] Implementar rollback automático se o smoke test falhar

## Tecnologias

![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-CI%2FCD-2088FF?logo=githubactions)
![AWS Lambda](https://img.shields.io/badge/AWS-Lambda-FF9900?logo=awslambda)
![Docker](https://img.shields.io/badge/Docker-Container-2496ED?logo=docker)
![Terraform](https://img.shields.io/badge/Terraform-IaC-623CE4?logo=terraform)
![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python)
