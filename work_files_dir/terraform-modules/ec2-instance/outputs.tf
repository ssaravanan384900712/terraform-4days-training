output "instance_id"      { value = aws_instance.this.id }
output "public_ip"        { value = aws_instance.this.public_ip }
output "ami_id"           { value = data.aws_ami.ubuntu.id }
output "private_key_path" { value = local_sensitive_file.private_key.filename }
output "ssh_command"      { value = "ssh -i ${pathexpand(var.private_key_path)} ubuntu@${aws_instance.this.public_ip}" }
