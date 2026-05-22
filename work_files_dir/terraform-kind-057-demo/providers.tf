terraform {
  required_version = ">= 1.3"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

# kind stores kubeconfig in ~/.kube/config — the kubernetes provider reads it automatically
# when config_path is set. Context: kind-terraform-kind-lab
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kind-terraform-kind-lab"
}
