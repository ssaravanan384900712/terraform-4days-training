# Generate SSH key pair using Terraform TLS provider
resource "tls_private_key" "demo" {
  algorithm = "ED25519"
}

# Save private key to local disk
resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.demo.private_key_openssh
  filename        = pathexpand(var.private_key_path)
  file_permission = "0600"
}

# Fetch latest Ubuntu 22.04 LTS AMI from Canonical
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Register Terraform-generated public key as AWS EC2 Key Pair
resource "aws_key_pair" "demo" {
  key_name   = var.key_name
  public_key = tls_private_key.demo.public_key_openssh
}

# Security group to allow SSH access
resource "aws_security_group" "ssh" {
  name        = "terraform-016-ssh-sg"
  description = "Allow SSH access to EC2 instance"

  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-016-ssh-sg"
  }
}

# Create EC2 instance
resource "aws_instance" "demo" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.demo.key_name
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  associate_public_ip_address = true

  tags = {
    Name = var.instance_name
  }
}
