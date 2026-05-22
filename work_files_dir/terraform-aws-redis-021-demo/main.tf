# Fetch default VPC and a subnet
data "aws_vpc" "default" { default = true }

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

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

resource "tls_private_key" "demo" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.demo.private_key_openssh
  filename        = pathexpand(var.private_key_path)
  file_permission = "0600"
}

resource "aws_key_pair" "demo" {
  key_name   = "terraform-021-demo-key"
  public_key = tls_private_key.demo.public_key_openssh
}

resource "aws_security_group" "ssh" {
  name        = "terraform-021-ssh-sg"
  description = "Allow SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "terraform-021-ssh-sg" }
}

# EC2 client in same VPC — used to run redis-cli against ElastiCache
resource "aws_instance" "redis_client" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.demo.key_name
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y redis-tools
  EOF

  tags = { Name = "terraform-021-redis-client" }
}

# Security group — allow Redis port from anywhere (demo only)
resource "aws_security_group" "redis" {
  name        = "terraform-021-redis-sg"
  description = "Allow Redis access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = var.redis_port
    to_port     = var.redis_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "terraform-021-redis-sg" }
}

# Subnet group for ElastiCache
resource "aws_elasticache_subnet_group" "demo" {
  name       = "terraform-021-redis-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
}

# Redis ElastiCache cluster
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "terraform-021-redis"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.1"
  port                 = var.redis_port
  subnet_group_name    = aws_elasticache_subnet_group.demo.name
  security_group_ids   = [aws_security_group.redis.id]

  tags = { Name = "terraform-021-redis" }
}
