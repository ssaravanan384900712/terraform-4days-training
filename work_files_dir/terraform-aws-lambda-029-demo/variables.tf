variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-south-1"
}

variable "name_prefix" {
  description = "Prefix applied to all resource names"
  type        = string
  default     = "terraform-029"
}

variable "owner" {
  description = "Owner tag value"
  type        = string
  default     = "saravanans"
}

variable "project" {
  description = "Project tag value"
  type        = string
  default     = "robochef.co"
}

variable "lambda_runtime" {
  description = "Lambda runtime identifier"
  type        = string
  default     = "python3.12"
}

variable "lambda_handler" {
  description = "Lambda handler in the form file.function"
  type        = string
  default     = "handler.lambda_handler"
}
