# Random suffix for globally unique bucket name
resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

# S3 Bucket
resource "aws_s3_bucket" "demo" {
  bucket = "${var.bucket_prefix}-${random_string.suffix.result}"

  tags = {
    Name = "terraform-017-demo"
  }
}

# Enable versioning
resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Upload a text file object
resource "aws_s3_object" "hello" {
  bucket       = aws_s3_bucket.demo.id
  key          = "hello.txt"
  content      = "Hello from Terraform! Bucket: ${aws_s3_bucket.demo.bucket}"
  content_type = "text/plain"
}

# Upload a JSON config object
resource "aws_s3_object" "config" {
  bucket       = aws_s3_bucket.demo.id
  key          = "config/app.json"
  content      = jsonencode({ env = "demo", version = "1.0", tool = "terraform" })
  content_type = "application/json"
}

# Read back the hello.txt object using a data source
data "aws_s3_object" "read_hello" {
  bucket = aws_s3_bucket.demo.id
  key    = aws_s3_object.hello.key

  depends_on = [aws_s3_object.hello]
}
