variable "replica_count_str" {
  description = "Replica count as string (simulating external data source)"
  type        = string
  default     = "3"
}

variable "debug_enabled_str" {
  description = "Boolean flag as string"
  type        = string
  default     = "true"
}

variable "env_list" {
  description = "Environments as list (may have duplicates)"
  type        = list(string)
  default     = ["dev", "staging", "prod", "staging", "dev"]
}

locals {
  replica_count  = tonumber(var.replica_count_str)
  debug_enabled  = tobool(var.debug_enabled_str)
  unique_envs    = toset(var.env_list)
  count_as_str   = tostring(local.replica_count)
}

resource "local_file" "types_demo" {
  filename = "/tmp/robochef-types.txt"
  content  = <<-EOT
    site=robochef.co
    owner=saravanans

    # tonumber: string -> number for arithmetic
    replica_count=${local.replica_count}
    replicas_doubled=${local.replica_count * 2}

    # tobool: string -> bool for conditionals
    debug_enabled=${local.debug_enabled}

    # toset: deduplicates list
    unique_envs=${join(", ", local.unique_envs)}
    original_count=${length(var.env_list)}
    unique_count=${length(local.unique_envs)}

    # tostring: number -> string for concatenation
    count_label=replica-count-${local.count_as_str}
  EOT
}

resource "random_string" "tokens" {
  for_each = toset(var.env_list)
  length   = 16
  special  = false
}

output "token_keys" {
  value = keys(random_string.tokens)
}
