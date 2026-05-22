terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Default provider — Mumbai (ap-south-1)
# Note: alias = "mumbai" means this is NOT the implicit default.
# Every resource must explicitly declare provider = aws.mumbai or aws.singapore.
provider "aws" {
  region = "ap-south-1"
  alias  = "mumbai"
}

# Second provider configuration — Singapore (ap-southeast-1)
provider "aws" {
  region = "ap-southeast-1"
  alias  = "singapore"
}
