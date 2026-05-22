variable "app_version" {
  description = "Changing this regenerates the app name"
  type        = string
  default     = "1.0.0"
}

resource "random_pet" "app" {
  keepers = {
    version = var.app_version
  }
  length = 2
}

output "app_name" {
  value = "app-${random_pet.app.id}-v${var.app_version}"
}
