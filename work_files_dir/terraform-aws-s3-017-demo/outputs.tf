output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.demo.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.demo.arn
}

output "bucket_region" {
  description = "S3 bucket region"
  value       = aws_s3_bucket.demo.region
}

output "hello_object_key" {
  description = "Key of the uploaded hello.txt object"
  value       = aws_s3_object.hello.key
}

output "hello_object_etag" {
  description = "ETag (MD5) of hello.txt"
  value       = aws_s3_object.hello.etag
}

output "hello_content_read_back" {
  description = "Content of hello.txt read back via data source"
  value       = data.aws_s3_object.read_hello.body
}

output "config_object_key" {
  description = "Key of the uploaded config/app.json object"
  value       = aws_s3_object.config.key
}

output "aws_cli_get_command" {
  description = "AWS CLI command to download hello.txt"
  value       = "aws s3 cp s3://${aws_s3_bucket.demo.bucket}/hello.txt ./hello_downloaded.txt"
}
