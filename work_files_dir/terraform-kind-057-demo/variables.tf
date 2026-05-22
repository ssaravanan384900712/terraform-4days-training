variable "cluster_context" {
  description = "kubectl context name for the kind cluster"
  type        = string
  default     = "kind-terraform-kind-lab"
}

variable "app_name" {
  description = "Application name used as prefix for all k8s resources"
  type        = string
  default     = "robochef"
}

variable "replicas" {
  description = "Number of pod replicas in the Deployment"
  type        = number
  default     = 2
}

variable "image" {
  description = "Container image to run"
  type        = string
  default     = "nginx:alpine"
}
