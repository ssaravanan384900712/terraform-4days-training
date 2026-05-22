output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.demo.id
}

output "public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.demo.public_ip
}

output "public_dns" {
  description = "Public DNS name of the EC2 instance"
  value       = aws_instance.demo.public_dns
}

output "ami_id" {
  description = "Ubuntu 22.04 AMI selected by the data source"
  value       = data.aws_ami.ubuntu.id
}

output "key_pair_name" {
  description = "AWS Key Pair name"
  value       = aws_key_pair.demo.key_name
}

output "private_key_file" {
  description = "Path to the local private key file"
  value       = local_file.private_key.filename
}

output "ssh_command" {
  description = "Paste this to SSH into the instance"
  value       = "ssh -i robochef-fp-052.pem ubuntu@${aws_instance.demo.public_ip}"
}

output "nginx_url" {
  description = "URL to verify nginx is running"
  value       = "http://${aws_instance.demo.public_ip}"
}
