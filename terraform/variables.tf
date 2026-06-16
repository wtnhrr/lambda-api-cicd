variable "aws_region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto"
  type        = string
  default     = "user-lambda-api"
}

variable "environment" {
  description = "Ambiente de deploy"
  type        = string
  default     = "production"
}
