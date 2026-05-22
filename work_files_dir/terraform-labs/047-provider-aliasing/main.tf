# ---------------------------------------------------------------------------
# Shared suffix — both buckets use the same random string so their names
# are clearly paired. random_string itself has no provider requirement.
# ---------------------------------------------------------------------------
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# ---------------------------------------------------------------------------
# S3 bucket in Mumbai (ap-south-1)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "mumbai" {
  provider = aws.mumbai                                         # <-- explicit alias
  bucket   = "robochef-mumbai-${random_string.suffix.result}"

  tags = {
    Name    = "robochef-mumbai"
    Owner   = "saravanans"
    Region  = "ap-south-1"
    Lab     = "047"
    Project = "robochef"
  }
}

# ---------------------------------------------------------------------------
# S3 bucket in Singapore (ap-southeast-1)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "singapore" {
  provider = aws.singapore                                      # <-- explicit alias
  bucket   = "robochef-singapore-${random_string.suffix.result}"

  tags = {
    Name    = "robochef-singapore"
    Owner   = "saravanans"
    Region  = "ap-southeast-1"
    Lab     = "047"
    Project = "robochef"
  }
}

# ---------------------------------------------------------------------------
# Data sources — confirm which region each aliased provider resolves to.
# Useful for outputs and for debugging misconfigured provider blocks.
# ---------------------------------------------------------------------------
data "aws_region" "mumbai" {
  provider = aws.mumbai
}

data "aws_region" "singapore" {
  provider = aws.singapore
}
