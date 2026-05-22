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
}

# ---------------------------------------------------------------------------
# API token — random_string forces replacement whenever any argument changes.
# create_before_destroy = true ensures the NEW token exists before the OLD
# one is removed from state (and from the file it populates).
# ---------------------------------------------------------------------------
resource "random_string" "api_token" {
  length  = var.token_length
  special = false
  upper   = false

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# App config file — depends on the token value.
# When the token is replaced, this file is also replaced.
# create_before_destroy here ensures the file is never absent between writes.
# ---------------------------------------------------------------------------
resource "local_file" "app_config" {
  filename = "/tmp/robochef-app-config.txt"
  content  = <<-EOT
    site=robochef.co
    owner=saravanans
    api_token=${random_string.api_token.result}
    token_length=${var.token_length}
  EOT

  lifecycle {
    create_before_destroy = true
  }
}

output "api_token" {
  description = "Current API token value"
  value       = random_string.api_token.result
}

output "config_file" {
  description = "Path of the written app config"
  value       = local_file.app_config.filename
}
