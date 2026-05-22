output "ubuntu_ami_id" {
  description = "Ubuntu AMI selected by Terraform"
  value       = data.aws_ami.ubuntu.id
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.demo.id
}

output "instance_public_ip" {
  description = "Public IP address of EC2 instance"
  value       = aws_instance.demo.public_ip
}

output "private_key_path" {
  description = "Path to the Terraform-generated private key on disk"
  value       = local_sensitive_file.private_key.filename
}

output "ssh_command" {
  description = "SSH command to connect to EC2"
  value       = "ssh -i ${pathexpand(var.private_key_path)} ubuntu@${aws_instance.demo.public_ip}"
}
