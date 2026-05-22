# Create AMI from the base instance (apply this after SSH modifications)
resource "aws_ami_from_instance" "custom" {
  name               = "terraform-020-custom-ami"
  source_instance_id = aws_instance.base.id
  snapshot_without_reboot = false

  tags = { Name = "terraform-020-custom-ami" }
}

# New instance launched from the custom AMI
resource "aws_instance" "from_ami" {
  ami                         = aws_ami_from_instance.custom.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.demo.key_name
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  associate_public_ip_address = true

  tags = { Name = "terraform-020-from-custom-ami" }
}
