# outputs.tf
output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.web.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.web.public_ip
}

output "private_key_path" {
  description = "Local path of the generated SSH private key"
  value       = local_sensitive_file.private_key.filename
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ${local_sensitive_file.private_key.filename} ubuntu@${aws_instance.web.public_ip}"
}

output "curl_command" {
  description = "curl command to verify nginx is serving robochef.co"
  value       = "curl http://${aws_instance.web.public_ip}"
}
