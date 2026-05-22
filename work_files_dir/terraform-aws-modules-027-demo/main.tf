resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

module "web_server" {
  source           = "../terraform-modules/ec2-instance"
  instance_name    = "robochef-web"
  instance_type    = "t3.micro"
  private_key_path = "~/.ssh/terraform-027-robochef"
  tags = {
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}

module "app_bucket" {
  source            = "../terraform-modules/s3-bucket"
  bucket_name       = "robochef-app-${random_string.suffix.result}"
  enable_versioning = true
  force_destroy     = true
  tags = {
    Owner = "saravanans"
    Site  = "robochef.co"
  }
}

module "chillbot_bucket" {
  source            = "../terraform-modules/s3-bucket"
  bucket_name       = "chillbotindia-app-${random_string.suffix.result}"
  enable_versioning = false
  force_destroy     = true
  tags = {
    Owner = "saravanans"
    Site  = "chillbotindia.com"
  }
}
