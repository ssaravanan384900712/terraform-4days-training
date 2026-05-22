variable "enable_debug_log" {
  description = "Create a debug log file for robochef.co?"
  type        = bool
  default     = true
}

resource "local_file" "debug_log" {
  count    = var.enable_debug_log ? 1 : 0
  filename = "/tmp/robochef-debug.log"
  content  = "Debug enabled for robochef.co\nOwner: saravanans\n"
}

output "debug_log_path" {
  value = var.enable_debug_log ? local_file.debug_log[0].filename : "debug disabled"
}

variable "environment" {
  description = "Deployment environment: dev, staging, or prod"
  type        = string
  default     = "dev"
}

resource "random_string" "api_key" {
  length  = var.environment == "prod" ? 32 : 16
  special = var.environment == "prod" ? true : false
}

resource "local_file" "app_settings" {
  filename = "/tmp/robochef-settings.txt"
  content  = <<-EOT
    environment=${var.environment}
    log_level=${var.environment == "prod" ? "ERROR" : "DEBUG"}
    replicas=${var.environment == "prod" ? 3 : 1}
    api_key_length=${var.environment == "prod" ? 32 : 16}
    site=robochef.co
    owner=saravanans
  EOT
}

output "api_key_length" {
  value = random_string.api_key.length
}

output "settings_file" {
  value = local_file.app_settings.filename
}

variable "features" {
  description = "Feature flags for robochef.co"
  type        = map(bool)
  default = {
    dark_mode     = true
    notifications = false
    analytics     = true
    beta_features = false
  }
}

resource "local_file" "enabled_features" {
  for_each = { for k, v in var.features : k => v if v == true }
  filename  = "/tmp/robochef-feature-${each.key}.txt"
  content   = "Feature ${each.key} is ENABLED for robochef.co\n"
}

output "enabled_features" {
  value = { for k, v in local_file.enabled_features : k => v.filename }
}

output "disabled_features" {
  value = [for k, v in var.features : k if v == false]
}

locals {
  tier = var.environment == "prod" ? "premium" : var.environment == "staging" ? "standard" : "free"

  # The above is equivalent to:
  # if env == "prod"     → "premium"
  # elif env == "staging" → "standard"
  # else                  → "free"
}

resource "local_file" "tier_info" {
  filename = "/tmp/robochef-tier.txt"
  content  = "Environment: ${var.environment}\nTier: ${local.tier}\nSite: robochef.co\n"
}

output "current_tier" {
  value = local.tier
}

output "api_key_value" {
  description = "API key — longer in prod for robochef.co"
  value       = random_string.api_key.result
  sensitive   = true
}

output "resource_summary" {
  value = {
    debug_enabled    = var.enable_debug_log
    environment      = var.environment
    tier             = local.tier
    features_enabled = length({ for k, v in var.features : k => v if v == true })
    features_total   = length(var.features)
  }
}
