resource "aws_s3_bucket" "app" {
  bucket        = "robochef-terraform-019-app-bucket-demo"
  force_destroy = true
  tags          = { Name = "terraform-019-app" }
}

output "app_bucket_name"  { value = aws_s3_bucket.app.bucket }
output "state_backend"    { value = "s3 + dynamodb locking" }
