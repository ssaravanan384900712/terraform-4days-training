variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}
variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
}
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}
variable "private_key_path" {
  description = "Path where the generated private key is saved"
  type        = string
  default     = "~/.ssh/terraform-module-ec2"
}
variable "allowed_ssh_cidr" {
  description = "CIDR allowed for SSH"
  type        = string
  default     = "0.0.0.0/0"
}
variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
