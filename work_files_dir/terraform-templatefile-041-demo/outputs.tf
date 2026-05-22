# outputs.tf
output "robochef_config_path" {
  description = "Path to the generated robochef.co nginx config"
  value       = local_file.robochef_nginx.filename
}

output "chillbot_config_path" {
  description = "Path to the generated chillbotindia.com nginx config"
  value       = local_file.chillbot_nginx.filename
}

output "robochef_config_preview" {
  description = "First 10 lines of the generated robochef config"
  value       = local.robochef_config
}
