variable "bucket_name" {
  description = "S3 bucket name (must be globally unique)"
  type        = string
}
variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}
variable "force_destroy" {
  description = "Delete all objects on bucket destroy"
  type        = bool
  default     = false
}
variable "tags" {
  description = "Tags to apply to the bucket"
  type        = map(string)
  default     = {}
}
