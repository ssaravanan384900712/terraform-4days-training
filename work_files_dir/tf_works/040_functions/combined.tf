locals {
  raw_sites = "Robochef.CO, Chillbot.IN, MyApp.IO"

  sites = [
    for s in split(",", local.raw_sites) :
    trimspace(lower(s))
  ]

  site_slugs = {
    for s in local.sites :
    s => replace(replace(s, ".", "-"), " ", "-")
  }

  site_summary = join("\n", [
    for s in local.sites :
    format("  %-20s → %s", s, local.site_slugs[s])
  ])

  config_json = jsonencode({
    owner     = "saravanans"
    sites     = local.sites
    slugs     = local.site_slugs
    generated = formatdate("YYYY-MM-DD", timestamp())
    checksum  = md5(join(",", local.sites))
  })
}

resource "local_file" "combined_demo" {
  filename = "/tmp/robochef-combined.txt"
  content  = <<-EOT
    owner=saravanans
    generated=${formatdate("YYYY-MM-DD", timestamp())}

    # raw input → cleaned list
    raw=${local.raw_sites}
    sites=${join(", ", local.sites)}
    site_count=${length(local.sites)}

    # slug map
    ${local.site_summary}

    # md5 fingerprint of site list
    checksum=${md5(join(",", local.sites))}

    # full config as JSON
    ${local.config_json}
  EOT
}
