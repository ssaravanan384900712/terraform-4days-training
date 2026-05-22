variable "aws_region" {
  description = "AWS region to deploy the EKS cluster"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "Name for the EKS cluster"
  type        = string
  default     = "terraform-033-eks"
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group (must be free-tier eligible on restricted accounts)"
  type        = string
  default     = "t3.small"
}

variable "app_name" {
  description = "Application name — used as prefix for k8s Namespace, Deployment, Service, ConfigMap"
  type        = string
  default     = "robochef"
}

variable "replicas" {
  description = "Number of pod replicas in the Deployment"
  type        = number
  default     = 1
}
