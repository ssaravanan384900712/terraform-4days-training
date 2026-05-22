terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# ── Part 1: create_before_destroy ────────────────────────────────────────────

resource "random_string" "token" {
  length  = 16
  special = false

  lifecycle {
    create_before_destroy = true
  }
}

output "token" {
  value     = random_string.token.result
  sensitive = true
}

# ── Part 2: prevent_destroy ───────────────────────────────────────────────────

resource "local_file" "robochef_config" {
  filename = "/tmp/robochef-critical-config.txt"
  content  = "site=robochef.co\nowner=saravanans\nenv=production"

  lifecycle {
    prevent_destroy = true
  }
}

output "config_path" {
  value = local_file.robochef_config.filename
}

# ── Part 3: ignore_changes ────────────────────────────────────────────────────

variable "app_content" {
  type    = string
  default = "version=1.0\nsite=robochef.co"
}

resource "local_file" "app_config" {
  filename = "/tmp/robochef-app-config.txt"
  content  = var.app_content

  lifecycle {
    ignore_changes = [content]
  }
}

output "app_config_path" {
  value = local_file.app_config.filename
}

# ── Part 4: replace_triggered_by ─────────────────────────────────────────────

resource "random_string" "version" {
  length  = 6
  special = false
  upper   = false

  keepers = {
    deploy_tag = "v1"
  }
}

resource "local_file" "app" {
  filename = "/tmp/robochef-app.txt"
  content  = "robochef app — deployment bundle"

  lifecycle {
    replace_triggered_by = [random_string.version]
  }
}

output "deploy_version" {
  value = random_string.version.result
}

output "app_file" {
  value = local_file.app.filename
}
