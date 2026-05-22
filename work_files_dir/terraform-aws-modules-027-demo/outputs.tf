output "web_instance_id" { value = module.web_server.instance_id }
output "web_public_ip" { value = module.web_server.public_ip }
output "web_ssh_command" { value = module.web_server.ssh_command }
output "app_bucket_name" { value = module.app_bucket.bucket_name }
output "app_bucket_arn" { value = module.app_bucket.bucket_arn }
output "chillbot_bucket_name" { value = module.chillbot_bucket.bucket_name }
output "app_versioning" { value = module.app_bucket.versioning_status }
output "chillbot_versioning" { value = module.chillbot_bucket.versioning_status }
