# outputs.tf
output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = try(aws_instance.web.public_ip, "not created")
}

output "private_key_path" {
  description = "Local path to the generated private key"
  value       = local_sensitive_file.private_key.filename
}

output "deploy_log" {
  description = "Local deploy log path written by local-exec provisioners"
  value       = "/tmp/deploy-log.txt"
}
