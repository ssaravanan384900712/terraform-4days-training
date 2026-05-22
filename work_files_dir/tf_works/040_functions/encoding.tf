locals {
  app_config = {
    site     = "robochef.co"
    owner    = "saravanans"
    env      = "prod"
    replicas = 3
    tags     = ["api", "web", "cache"]
  }
}

resource "local_file" "json_config" {
  filename = "/tmp/robochef-config.json"
  content  = jsonencode(local.app_config)
}

resource "local_file" "yaml_config" {
  filename = "/tmp/robochef-config.yaml"
  content  = yamlencode(local.app_config)
}

resource "local_file" "encoded_secret" {
  filename = "/tmp/robochef-secret.txt"
  content  = <<-EOT
    # base64 encoding for config transport
    encoded=${base64encode("robochef.co:saravanans:prod")}
    decoded=${base64decode(base64encode("robochef.co:saravanans:prod"))}

    # json round-trip
    json_site=${jsondecode(jsonencode(local.app_config)).site}
  EOT
}

output "json_config_path" {
  value = local_file.json_config.filename
}
