output "base_instance_ip"     { value = aws_instance.base.public_ip }
output "base_instance_id"     { value = aws_instance.base.id }
output "ssh_command_base"     { value = "ssh -i ${pathexpand(var.private_key_path)} ubuntu@${aws_instance.base.public_ip}" }
output "custom_ami_id"        { value = aws_ami_from_instance.custom.id }
output "new_instance_ip"      { value = aws_instance.from_ami.public_ip }
output "ssh_command_new"      { value = "ssh -i ${pathexpand(var.private_key_path)} ubuntu@${aws_instance.from_ami.public_ip}" }
