variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "private_key_path" {
  type    = string
  default = "~/.ssh/terraform-020-demo"
}
