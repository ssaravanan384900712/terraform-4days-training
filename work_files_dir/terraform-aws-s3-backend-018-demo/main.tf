resource "aws_s3_bucket" "app" {
  bucket = "terraform-018-app-bucket-demo"
  force_destroy = true

  tags = { Name = "terraform-018-app" }
}

output "app_bucket_name" {
  value = aws_s3_bucket.app.bucket
}
