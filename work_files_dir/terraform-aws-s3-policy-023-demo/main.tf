resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

# Primary bucket with versioning
resource "aws_s3_bucket" "main" {
  bucket        = "${var.bucket_prefix}-${random_string.suffix.result}"
  force_destroy = true
  tags          = { Name = "robochef-023-main", Owner = "saravanans", Site = "robochef.co" }
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration { status = "Enabled" }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "main" {
  bucket                  = aws_s3_bucket.main.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket policy — allow read/write only from this account
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource  = [aws_s3_bucket.main.arn, "${aws_s3_bucket.main.arn}/*"]
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.main]
}

# Upload v1 of an object
resource "aws_s3_object" "config_v1" {
  bucket       = aws_s3_bucket.main.id
  key          = "config/settings.json"
  content      = jsonencode({ version = "1.0", app = "robochef", env = "demo" })
  content_type = "application/json"
}
