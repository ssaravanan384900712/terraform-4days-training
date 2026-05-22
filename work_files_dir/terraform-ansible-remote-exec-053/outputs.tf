# outputs.tf

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.web.id
}

output "public_ip" {
  description = "Public IP of the web server"
  value       = aws_instance.web.public_ip
}

output "public_dns" {
  description = "Public DNS of the web server"
  value       = aws_instance.web.public_dns
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i robochef_demo.pem ubuntu@${aws_instance.web.public_ip}"
}

output "curl_command" {
  description = "curl command to verify the web server"
  value       = "curl http://${aws_instance.web.public_ip}"
}

output "key_algorithm" {
  description = "Algorithm used for the SSH key"
  value       = tls_private_key.demo.algorithm
}
