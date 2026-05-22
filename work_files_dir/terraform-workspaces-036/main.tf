# main.tf

# ------------------------------------------------------------------
# random_string — generates a unique ID per workspace.
# Because each workspace has its own state, this resource creates
# a NEW random string when you first apply in each workspace, then
# keeps the same string on subsequent applies in that workspace.
# ------------------------------------------------------------------
resource "random_string" "env_id" {
  length  = 8
  upper   = false
  special = false
}

# ------------------------------------------------------------------
# locals — workspace-aware configuration map
#
# terraform.workspace is a built-in variable that holds the name of
# the currently selected workspace ("default", "dev", "staging", etc.)
#
# We use lookup() with a default so that any unrecognized workspace
# name falls back to the "default" config rather than erroring.
# ------------------------------------------------------------------
locals {
  env_config = {
    default = { site = "robochef.co", tier = "dev",     note = "default workspace — treat as dev" }
    dev     = { site = "robochef.co", tier = "dev",     note = "development environment" }
    staging = { site = "robochef.co", tier = "staging", note = "pre-production staging environment" }
    prod    = { site = "robochef.co", tier = "prod",    note = "production — handle with care" }
  }

  # lookup() returns env_config[terraform.workspace] if it exists,
  # otherwise returns env_config["default"] as the fallback.
  config = lookup(local.env_config, terraform.workspace, local.env_config["default"])
}

# ------------------------------------------------------------------
# local_file — writes an environment-specific config file.
#
# The filename includes terraform.workspace so each workspace writes
# to a different path — making it easy to verify isolation.
# ------------------------------------------------------------------
resource "local_file" "env_config" {
  filename        = "/tmp/robochef-${terraform.workspace}-config.txt"
  file_permission = "0644"
  content         = <<-EOT
    Workspace : ${terraform.workspace}
    Site      : ${local.config.site}
    Tier      : ${local.config.tier}
    Note      : ${local.config.note}
    Unique ID : ${random_string.env_id.result}
    Written   : ${timestamp()}
  EOT
}
