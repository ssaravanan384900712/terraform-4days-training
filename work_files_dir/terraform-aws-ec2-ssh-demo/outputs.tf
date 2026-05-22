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

output "ssh_command" {
  description = "Manual SSH command to connect to EC2"
  value       = "ssh -i ~/.ssh/terraform-aws-demo ubuntu@${aws_instance.demo.public_ip}"
}
