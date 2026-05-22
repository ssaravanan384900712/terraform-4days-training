variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name (must be lowercase)"
  type        = string
  default     = "terraform-017-demo"
}
