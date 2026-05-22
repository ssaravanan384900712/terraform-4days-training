variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_port" {
  type    = number
  default = 6379
}

variable "private_key_path" {
  type    = string
  default = "~/.ssh/terraform-021-demo"
}
