resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "aws_secretsmanager_secret" "robochef_db" {
  name                    = "terraform-032-robochef-db-${random_string.suffix.result}"
  description             = "RoboChef database credentials managed by Terraform"
  recovery_window_in_days = 0

  tags = {
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}

resource "aws_secretsmanager_secret_version" "robochef_db" {
  secret_id = aws_secretsmanager_secret.robochef_db.id
  secret_string = jsonencode({
    username = "robochef"
    password = var.db_password
    host     = "robochef-rds.ap-south-1.rds.amazonaws.com"
    dbname   = "robochefdb"
  })
}
