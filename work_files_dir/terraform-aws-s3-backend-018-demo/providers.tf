terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    # filled in at runtime via -backend-config
  }
}

provider "aws" {
  region = var.aws_region
}
