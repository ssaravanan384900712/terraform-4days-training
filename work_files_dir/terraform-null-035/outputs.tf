# outputs.tf

output "greeting_file" {
  description = "Path to the greeting file written by Demo 1"
  value       = "/tmp/robochef-greeting.txt"
}

output "config_file" {
  description = "Path to the JSON config file written by Demo 2"
  value       = local_file.config.filename
}

output "deployed_version" {
  description = "The app version that was deployed in Demo 3"
  value       = null_resource.deploy.triggers.version
}

output "modern_greeting_file" {
  description = "Path to the greeting file written by Demo 4 (terraform_data)"
  value       = "/tmp/robochef-greeting-modern.txt"
}

output "version_store_output" {
  description = "The input value stored inside terraform_data.version_store"
  value       = terraform_data.version_store.output
}
