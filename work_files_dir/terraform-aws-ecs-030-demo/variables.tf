variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-south-1"
}

variable "prefix" {
  description = "Resource name prefix for all resources in this lab"
  type        = string
  default     = "terraform-030"
}

variable "ecr_repo_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "terraform-030-robochef-app"
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = "terraform-030-cluster"
}

variable "container_image" {
  description = "Docker image for the ECS task (using public nginx for simplicity)"
  type        = string
  default     = "nginx:latest"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 80
}

variable "task_cpu" {
  description = "CPU units for the Fargate task (1 vCPU = 1024)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memory (MiB) for the Fargate task"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Desired number of ECS task instances"
  type        = number
  default     = 1
}
