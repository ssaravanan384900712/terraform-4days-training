variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "EKS cluster name (from lab 033)"
  type        = string
  default     = "terraform-033-eks"
}

variable "app_name" {
  description = "Application name prefix"
  type        = string
  default     = "robochef"
}

variable "replicas" {
  description = "Number of deployment replicas"
  type        = number
  default     = 2
}
