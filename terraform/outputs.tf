output "api_url" {
  description = "URL pública da API"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "ecr_repository_url" {
  description = "URL do repositório ECR para push de imagens"
  value       = aws_ecr_repository.lambda_repo.repository_url
}

output "lambda_function_name" {
  description = "Nome da função Lambda"
  value       = aws_lambda_function.api.function_name
}

output "lambda_arn" {
  description = "ARN da função Lambda"
  value       = aws_lambda_function.api.arn
}
