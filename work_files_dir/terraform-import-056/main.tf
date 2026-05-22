resource "aws_vpc" "imported" {
  cidr_block           = "10.99.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = false

  tags = {
    Name    = "my-imported-vpc"
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}
