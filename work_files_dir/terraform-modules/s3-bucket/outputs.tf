output "bucket_name"       { value = aws_s3_bucket.this.bucket }
output "bucket_arn"        { value = aws_s3_bucket.this.arn }
output "bucket_id"         { value = aws_s3_bucket.this.id }
output "versioning_status" { value = var.enable_versioning ? "Enabled" : "Suspended" }
