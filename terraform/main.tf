terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ECR - Elastic Container Registry
# Repositório privado para armazenar as imagens Docker da Lambda
resource "aws_ecr_repository" "lambda_repo" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE" # permite sobrescrever a tag "latest"

  image_scanning_configuration {
    scan_on_push = true # escaneia vulnerabilidades automaticamente a cada push
  }

  tags = {
    Name    = var.project_name
    Project = var.project_name
  }
}

# Política de ciclo de vida
resource "aws_ecr_lifecycle_policy" "lambda_repo" {
  repository = aws_ecr_repository.lambda_repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Manter apenas as ultimas 5 imagens"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

# IAM Role para a Lambda
# A Lambda precisa de uma Role IAM para ter permissão de executar na AWS
# Princípio do menor privilégio
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-role"

  # Assume role policy: define quem pode "vestir" essa role
  # Aqui dizemos que o serviço Lambda pode assumir essa role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = {
    Name    = "${var.project_name}-role"
    Project = var.project_name
  }
}

# Política gerenciada da AWS que permite à Lambda escrever logs no CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function
resource "aws_lambda_function" "api" {
  function_name = var.project_name
  role          = aws_iam_role.lambda_role.arn

  # O image_uri aponta para o ECR — o CI/CD vai atualizar essa imagem
  package_type = "Image"
  image_uri    = "${aws_ecr_repository.lambda_repo.repository_url}:latest"

  memory_size = 128  # suficiente para nossa API simples
  timeout     = 30   # tempo máximo de execução

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tags = {
    Name    = var.project_name
    Project = var.project_name
  }

  # O CI/CD (GitHub Actions) é responsável por atualizar a imagem
  # Se não ignorarmos, o Terraform reverteria os deploys do CI/CD
  lifecycle {
    ignore_changes = [image_uri]
  }
}

# API Gateway HTTP API
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
  }

  tags = {
    Name    = "${var.project_name}-api"
    Project = var.project_name
  }
}

# Integração: conecta o API Gateway à Lambda
resource "aws_apigatewayv2_integration" "lambda" {
  api_id             = aws_apigatewayv2_api.http_api.id
  integration_type   = "AWS_PROXY" # repassa o evento completo para a Lambda
  integration_uri    = aws_lambda_function.api.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

# Rota: qualquer método em qualquer path vai para a Lambda
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "$default" # captura todas as rotas não mapeadas
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# Stage: ambiente de deploy
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true # deploya automaticamente quando houver mudanças

  tags = {
    Name    = "${var.project_name}-stage"
    Project = var.project_name
  }
}

# Permissão para o API Gateway invocar a Lambda
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
