# outputs.tf

output "workspace" {
  description = "The currently selected workspace"
  value       = terraform.workspace
}

output "config_file" {
  description = "Path to the config file written for this workspace"
  value       = local_file.env_config.filename
}

output "env_id" {
  description = "The random ID unique to this workspace"
  value       = random_string.env_id.result
}

output "tier" {
  description = "The tier label for this workspace"
  value       = local.config.tier
}
