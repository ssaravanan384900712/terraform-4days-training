data "aws_vpc" "default" { default = true }

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "aws_security_group" "rds" {
  name        = "terraform-028-rds-sg"
  description = "Allow Postgres from anywhere (demo only)"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "terraform-028-rds-sg", Owner = "saravanans" }
}

resource "aws_db_subnet_group" "demo" {
  name       = "terraform-028-rds-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
  tags       = { Name = "terraform-028-rds-subnet-group" }
}

resource "aws_db_instance" "postgres" {
  identifier           = "terraform-028-postgres"
  engine               = "postgres"
  engine_version       = "16.14"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  storage_type         = "gp2"
  db_name              = "robochefdb"
  username             = "robochef"
  password             = var.db_password
  db_subnet_group_name = aws_db_subnet_group.demo.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot  = true
  publicly_accessible  = true
  multi_az             = false

  tags = { Name = "terraform-028-postgres", Owner = "saravanans", Project = "robochef.co" }
}
