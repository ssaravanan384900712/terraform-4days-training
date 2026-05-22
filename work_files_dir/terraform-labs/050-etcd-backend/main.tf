terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }

  # ---------------------------------------------------------------------------
  # etcdv3 backend — stores terraform.tfstate in etcd under the given prefix.
  # Note: the backend type is "etcdv3", NOT "etcd" (v2 is deprecated).
  # ---------------------------------------------------------------------------
  backend "etcdv3" {
    endpoints = ["localhost:2379"]  # etcd client endpoint(s)
    lock      = true                # Enable distributed locking
    prefix    = "terraform-state/"  # Key prefix in etcd KV store
  }
}

resource "random_string" "deploy_id" {
  length  = 8
  upper   = false
  special = false
}

resource "local_file" "deploy_config" {
  filename = "/tmp/robochef-etcd-demo.txt"
  content  = "site=robochef.co\nowner=saravanans\ndeploy_id=${random_string.deploy_id.result}\n"
}

output "deploy_id" {
  description = "Random deployment ID stored in etcd-backed state"
  value       = random_string.deploy_id.result
}

output "config_file" {
  description = "Path of the generated config file"
  value       = local_file.deploy_config.filename
}
