# variables.tf
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "ami_id" {
  description = "Ubuntu 22.04 LTS AMI in ap-south-1"
  type        = string
  default     = "ami-0f58b397bc5c1f2e8"   # Ubuntu 22.04 ap-south-1 (verify before use)
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}
