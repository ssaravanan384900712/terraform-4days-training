# variables.tf
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "ami_id" {
  description = "Ubuntu 22.04 LTS AMI for ap-south-1"
  type        = string
  default     = "ami-0f58b397bc5c1f2e8"  # verify the latest AMI before use
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "app_name" {
  description = "Application name — used in nginx config and tags"
  type        = string
  default     = "robochef"
}

variable "app_domain" {
  description = "Domain name for the nginx virtual host"
  type        = string
  default     = "robochef.co"
}
