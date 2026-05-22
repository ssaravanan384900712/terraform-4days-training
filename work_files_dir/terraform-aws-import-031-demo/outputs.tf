output "instance_id" {
  description = "The ID of the imported EC2 instance"
  value       = aws_instance.imported.id
}

output "public_ip" {
  description = "The public IP address of the imported EC2 instance"
  value       = aws_instance.imported.public_ip
}
