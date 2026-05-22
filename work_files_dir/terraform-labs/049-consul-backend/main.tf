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
  # Consul backend — stores terraform.tfstate in Consul's KV store.
  # The backend block cannot use variables or locals; values must be literals.
  # ---------------------------------------------------------------------------
  backend "consul" {
    address = "localhost:8500"   # HTTP address of the Consul agent
    scheme  = "http"             # http (dev) or https (production with TLS)
    path    = "tf/robochef-state"  # KV path where state is written
    lock    = true               # Enable session-based locking
    gzip    = false              # Don't compress state (easier to read raw)
  }
}

resource "random_string" "site_id" {
  length  = 8
  upper   = false
  special = false
}

resource "local_file" "site_config" {
  filename = "/tmp/robochef-consul-demo.txt"
  content  = "site=robochef.co\nowner=saravanans\nid=${random_string.site_id.result}\n"
}

output "site_id" {
  description = "Random site identifier stored in Consul-backed state"
  value       = random_string.site_id.result
}

output "config_file" {
  description = "Path of the generated config file"
  value       = local_file.site_config.filename
}
