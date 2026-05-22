locals {
  sample_content = file("${path.module}/sample.txt")
  sample_hash    = filemd5("${path.module}/sample.txt")
  providers_hash = filemd5("${path.module}/providers.tf")
}

resource "local_file" "filesystem_demo" {
  filename = "/tmp/robochef-filesystem.txt"
  content  = <<-EOT
    # file() reads file content at plan time
    sample_content:
    ${local.sample_content}

    # filemd5() checksums for change detection
    sample_md5=${local.sample_hash}
    providers_md5=${local.providers_hash}

    # path functions
    module_path=${abspath(path.module)}
    sample_basename=${basename("${path.module}/sample.txt")}
    sample_dirname=${dirname("${path.module}/sample.txt")}
  EOT
}
