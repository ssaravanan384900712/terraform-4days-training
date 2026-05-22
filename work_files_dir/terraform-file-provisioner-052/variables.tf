variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "project_name" {
  description = "Short name used in resource names and tags"
  type        = string
  default     = "robochef-fp-052"
}

variable "owner" {
  description = "Owner tag value"
  type        = string
  default     = "saravanans"
}

variable "project_tag" {
  description = "Project tag value"
  type        = string
  default     = "robochef.co"
}
