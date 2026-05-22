locals {
  site_md5    = md5("robochef.co")
  site_sha256 = sha256("robochef.co")
  owner_sha256 = sha256("saravanans")
  file_hash   = filemd5("${path.module}/sample.txt")
}

resource "local_file" "hash_demo" {
  filename = "/tmp/robochef-hashes.txt"
  content  = <<-EOT
    site=robochef.co
    owner=saravanans

    # md5 (fast, not crypto-safe — use for checksums only)
    site_md5=${local.site_md5}

    # sha256 (stronger — use for integrity checks)
    site_sha256=${local.site_sha256}
    owner_sha256=${local.owner_sha256}

    # filemd5 — hash a file for change detection
    sample_file_md5=${local.file_hash}

    # unique ID from hash (first 8 chars of md5)
    deploy_id=${substr(local.site_md5, 0, 8)}
  EOT
}

resource "local_file" "htpasswd" {
  filename = "/tmp/robochef-htpasswd.txt"
  content  = "saravanans:${bcrypt("robochef-secret-password")}\n"
}
