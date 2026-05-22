output "robochef_db_host" {
  value = data.vault_generic_secret.robochef_db.data["host"]
  # NOT sensitive — just the host
}

output "robochef_db_username" {
  value = data.vault_generic_secret.robochef_db.data["username"]
}

output "robochef_db_password" {
  sensitive = true   # REQUIRED for sensitive values
  value     = data.vault_generic_secret.robochef_db.data["password"]
}

output "config_files" {
  value = [local_file.app_config.filename, local_file.chillbot_config.filename]
}
