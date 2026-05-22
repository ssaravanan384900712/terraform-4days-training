# variables.tf

variable "app_version" {
  description = "Application version string. Change this to trigger the deploy null_resource."
  type        = string
  default     = "1.0.0"
}

variable "owner" {
  description = "Owner tag embedded in generated files."
  type        = string
  default     = "saravanans"
}

variable "site" {
  description = "Site name embedded in generated files."
  type        = string
  default     = "robochef.co"
}
