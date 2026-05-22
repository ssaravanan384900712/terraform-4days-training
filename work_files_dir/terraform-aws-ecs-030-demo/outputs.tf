output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer — curl this to reach nginx"
  value       = "http://${aws_lb.app.dns_name}"
}

output "ecr_repository_url" {
  description = "ECR repository URL (use this to push custom images later)"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.app.name
}

output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition (includes revision)"
  value       = aws_ecs_task_definition.app.arn
}

output "aws_account_id" {
  description = "AWS account ID (useful for constructing ECR push commands)"
  value       = data.aws_caller_identity.current.account_id
}
