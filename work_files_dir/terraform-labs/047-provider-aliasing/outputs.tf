output "mumbai_bucket_name" {
  description = "Name of the S3 bucket created in ap-south-1 (Mumbai)"
  value       = aws_s3_bucket.mumbai.bucket
}

output "singapore_bucket_name" {
  description = "Name of the S3 bucket created in ap-southeast-1 (Singapore)"
  value       = aws_s3_bucket.singapore.bucket
}

output "mumbai_region" {
  description = "Resolved region name from the Mumbai provider"
  value       = data.aws_region.mumbai.name
}

output "singapore_region" {
  description = "Resolved region name from the Singapore provider"
  value       = data.aws_region.singapore.name
}
