data "aws_caller_identity" "current" {}

# IAM User
resource "aws_iam_user" "demo" {
  name = var.username
  tags = { Owner = "saravanans", Project = "robochef.co" }
}

# IAM Group
resource "aws_iam_group" "demo" {
  name = "robochef-demo-group"
}

resource "aws_iam_group_membership" "demo" {
  name  = "robochef-demo-membership"
  group = aws_iam_group.demo.name
  users = [aws_iam_user.demo.name]
}

# Custom policy — read-only S3 access
resource "aws_iam_policy" "s3_read" {
  name        = "robochef-s3-read-only"
  description = "Allow S3 ListBucket and GetObject"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListAllMyBuckets", "s3:GetObject", "s3:ListBucket"]
      Resource = "*"
    }]
  })
}

# Attach policy to group
resource "aws_iam_group_policy_attachment" "s3_read" {
  group      = aws_iam_group.demo.name
  policy_arn = aws_iam_policy.s3_read.arn
}

# IAM Role (assumable by EC2)
resource "aws_iam_role" "ec2_role" {
  name = "robochef-ec2-demo-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Owner = "saravanans", Site = "chillbotindia.com" }
}

# Attach AWS managed ReadOnlyAccess to the role
resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Instance profile (wraps role for EC2 use)
resource "aws_iam_instance_profile" "ec2" {
  name = "robochef-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}
