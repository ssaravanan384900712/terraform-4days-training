output "bucket_name" { value = aws_s3_bucket.main.bucket }
output "bucket_arn" { value = aws_s3_bucket.main.arn }
output "account_id" { value = data.aws_caller_identity.current.account_id }
output "versioning" { value = "Enabled" }
output "policy_applied" { value = "Account-only read/write policy" }
output "list_versions_cmd" {
  value = "aws s3api list-object-versions --bucket ${aws_s3_bucket.main.bucket} --key config/settings.json --region ${var.aws_region}"
}
