output "secret_arn" {
  description = "The ARN of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.robochef_db.arn
}

output "secret_name" {
  description = "The name of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.robochef_db.name
}

output "get_secret_cmd" {
  description = "AWS CLI command to retrieve the secret value"
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.robochef_db.name} --region ${var.aws_region} --query SecretString --output text | jq ."
}
