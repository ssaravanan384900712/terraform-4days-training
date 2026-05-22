variable "site_name" {
  default = "Robochef"
}

variable "domain_suffix" {
  default = ".co"
}

locals {
  site_lower  = lower(var.site_name)
  site_upper  = upper(var.site_name)
  full_domain = format("%s%s", lower(var.site_name), var.domain_suffix)
  slug        = replace(lower(var.site_name), " ", "-")

  tags_raw    = "api,web,database,cache"
  tags_list   = split(",", local.tags_raw)
  tags_joined = join(" | ", local.tags_list)
}

resource "local_file" "string_demo" {
  filename = "/tmp/robochef-strings.txt"
  content  = <<-EOT
    site_lower=${local.site_lower}
    site_upper=${local.site_upper}
    full_domain=${local.full_domain}
    slug=${local.slug}
    tags=${local.tags_joined}
    first_tag=${local.tags_list[0]}
    banner=${format("=== %s (%s) ===", local.full_domain, "saravanans")}
  EOT
}
