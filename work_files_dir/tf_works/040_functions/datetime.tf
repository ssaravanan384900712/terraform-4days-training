locals {
  build_timestamp = timestamp()
  build_date      = formatdate("YYYY-MM-DD", local.build_timestamp)
  build_datetime  = formatdate("YYYY-MM-DD hh:mm:ss", local.build_timestamp)
  build_tag       = formatdate("YYYYMMDDhhmmss", local.build_timestamp)
}

resource "local_file" "build_info" {
  filename = "/tmp/robochef-build.txt"
  content  = <<-EOT
    site=robochef.co
    owner=saravanans
    build_timestamp=${local.build_timestamp}
    build_date=${local.build_date}
    build_datetime=${local.build_datetime}
    build_tag=${local.build_tag}
  EOT
}
