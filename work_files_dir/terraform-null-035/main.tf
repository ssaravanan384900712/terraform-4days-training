# main.tf

###############################################################
# DEMO 1 — null_resource with timestamp() trigger
#
# timestamp() returns the current UTC time as a string.
# Because the trigger value changes on every plan, Terraform
# always considers this resource "changed" and re-creates it —
# which re-runs the local-exec provisioner on every apply.
#
# Use case: "I want this shell command to run every time I apply."
###############################################################

resource "null_resource" "greet" {
  triggers = {
    always_run = timestamp()   # new value on every plan → always re-creates
  }

  provisioner "local-exec" {
    command = "echo 'Hello from ${var.site} at $(date)' > /tmp/robochef-greeting.txt"
  }
}


###############################################################
# DEMO 2 — depends_on: null_resource waits for local_file
#
# local_file.config writes a JSON file to /tmp/.
# null_resource.process_config must run AFTER that file exists.
#
# Terraform can infer dependencies from attribute references
# (e.g., referencing local_file.config.filename inside the
# null_resource would be enough). But provisioner commands are
# opaque strings — Terraform cannot see that the command reads
# the file. So we use explicit depends_on to be safe.
###############################################################

resource "local_file" "config" {
  filename        = "/tmp/robochef-config.json"
  file_permission = "0644"
  content = jsonencode({
    site    = var.site
    owner   = var.owner
    version = var.app_version
    note    = "Written by Terraform local_file resource"
  })
}

resource "null_resource" "process_config" {
  # explicit dependency — Terraform will not start this resource
  # until local_file.config has been created successfully.
  depends_on = [local_file.config]

  triggers = {
    # Re-run whenever the config file content changes.
    # We use the file content hash as the trigger value.
    config_content = local_file.config.content
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "--- Config file contents ---"
      cat /tmp/robochef-config.json
      echo ""
      echo "Config processed for ${var.site}!"
    EOT
  }
}


###############################################################
# DEMO 3 — trigger on variable change only
#
# Unlike Demo 1, this trigger is tied to var.app_version.
# The null_resource is only re-created (and the provisioner
# re-run) when you change the variable value.
#
# First apply  → creates, runs provisioner
# Second apply (same version) → no change, provisioner skipped
# Apply with -var="app_version=1.1.0" → re-creates, runs again
###############################################################

resource "null_resource" "deploy" {
  triggers = {
    version = var.app_version   # only changes when app_version changes
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Deploying ${var.site} version ${var.app_version}"
      echo "Deploy timestamp: $(date)"
      echo "${var.app_version}" > /tmp/robochef-deployed-version.txt
      echo "Deployment complete."
    EOT
  }
}


###############################################################
# DEMO 4 — terraform_data (modern replacement for null_resource)
#
# terraform_data is a built-in resource introduced in Terraform 1.4.
# It works identically to null_resource but:
#   - No provider needed (no hashicorp/null in required_providers)
#   - The trigger map is called "triggers_replace" (not "triggers")
#   - It can also store arbitrary "input" values in state
#
# This block does the same job as null_resource.greet in Demo 1.
###############################################################

resource "terraform_data" "greet_modern" {
  triggers_replace = {
    always_run = timestamp()   # same pattern — re-runs every apply
  }

  provisioner "local-exec" {
    command = "echo 'Hello from ${var.site} (terraform_data) at $(date)' > /tmp/robochef-greeting-modern.txt"
  }
}

# terraform_data also accepts an "input" value that is stored in state
# and exposed as the "output" attribute. Useful for passing computed
# values through the resource lifecycle without a separate output block.
resource "terraform_data" "version_store" {
  input = {
    site    = var.site
    version = var.app_version
    owner   = var.owner
  }
}
