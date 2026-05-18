# Hands-On 3.7 --- Terraform AWS Provider Deep Dive

**File:** `main.tf`, `lambda/`, `tfsec` scan output

---

## Concept

The AWS provider is Terraform's most-used provider, with 1000+ resource types. This lab covers authentication best practices, tagging strategies, compliance scanning, Lambda deployment, and troubleshooting common AWS errors.

```
Terraform Core
     |
     | gRPC
     v
AWS Provider (terraform-provider-aws)
     |
     | AWS SDK (Go)
     v
+----+----+----+----+----+
| EC2| S3 |IAM |RDS |... |  AWS APIs
+----+----+----+----+----+
```

---

## 1. AWS Provider Authentication

### Authentication Chain (Priority Order)

```
1. Static credentials in provider block     (NEVER do this)
2. Environment variables                    (CI/CD pipelines)
3. Shared credentials file (~/.aws/creds)   (Local development)
4. Instance profile / Task role             (EC2/ECS workloads)
5. OIDC / Web identity token                (GitHub Actions)
```

### Method 1: Environment Variables (Recommended for CI/CD)

```bash
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_DEFAULT_REGION="us-east-1"

# Optional: for assuming a role
export AWS_SESSION_TOKEN="FwoGZX..."
```

```hcl
# No credentials in the provider block
provider "aws" {
  region = "us-east-1"
}
```

### Method 2: AWS CLI Profile (Recommended for Local Dev)

```bash
# Configure a named profile
aws configure --profile terraform-dev
# Enter: Access Key, Secret Key, Region, Output format

# Use the profile
export AWS_PROFILE=terraform-dev
terraform plan
```

```hcl
provider "aws" {
  region  = "us-east-1"
  profile = "terraform-dev"
}
```

### Method 3: IAM Instance Profile (Recommended for EC2/ECS)

```hcl
# No credentials needed - the instance role provides them
provider "aws" {
  region = "us-east-1"
}
```

```
EC2 Instance
  └── Instance Profile
       └── IAM Role: terraform-runner
            └── Policy: AdministratorAccess (or scoped policy)
```

### Method 4: Assume Role (Cross-Account or Least Privilege)

```hcl
provider "aws" {
  region = "us-east-1"

  assume_role {
    role_arn     = "arn:aws:iam::987654321098:role/TerraformDeployRole"
    session_name = "terraform-deploy"
    external_id  = "unique-external-id"
  }
}
```

### Method 5: OIDC for GitHub Actions

```hcl
# GitHub Actions uses OIDC - no long-lived credentials
provider "aws" {
  region = "us-east-1"
}
```

```yaml
# In GitHub Actions workflow:
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789012:role/github-oidc-role
    aws-region: us-east-1
```

### Multiple AWS Accounts

```hcl
# Default provider (account A)
provider "aws" {
  region = "us-east-1"
}

# Aliased provider (account B)
provider "aws" {
  alias  = "production"
  region = "us-east-1"

  assume_role {
    role_arn = "arn:aws:iam::999888777666:role/TerraformRole"
  }
}

# Use in resources
resource "aws_s3_bucket" "dev" {
  bucket = "dev-data"
  # Uses default provider (account A)
}

resource "aws_s3_bucket" "prod" {
  provider = aws.production
  bucket   = "prod-data"
  # Uses aliased provider (account B)
}
```

---

## 2. Resource Tagging Strategy

### Default Tags (Provider-Level)

```hcl
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Project     = "acme-platform"
      Environment = "production"
      CostCenter  = "engineering-123"
      Owner       = "platform-team"
    }
  }
}
```

Every resource created by this provider automatically gets these tags. Resource-level tags merge with (and override) default tags.

### Tagging Convention

| Tag Key | Purpose | Example |
|---------|---------|---------|
| `Name` | Human-readable name | `prod-web-server-01` |
| `Environment` | Deployment stage | `dev`, `staging`, `prod` |
| `ManagedBy` | How it was created | `terraform` |
| `Project` | Business project | `acme-platform` |
| `CostCenter` | Billing allocation | `engineering-123` |
| `Owner` | Responsible team | `platform-team` |
| `Compliance` | Regulatory tag | `pci`, `hipaa`, `sox` |
| `DataClassification` | Data sensitivity | `public`, `internal`, `confidential` |

### Querying by Tags

```hcl
# Find all resources with a specific tag
data "aws_resourcegroupstaggingapi_resources" "terraform_managed" {
  tag_filter {
    key    = "ManagedBy"
    values = ["terraform"]
  }
}

output "terraform_managed_resources" {
  value = data.aws_resourcegroupstaggingapi_resources.terraform_managed.resource_tag_mapping_list[*].resource_arn
}

# Find resources by project
data "aws_resourcegroupstaggingapi_resources" "by_project" {
  tag_filter {
    key    = "Project"
    values = ["acme-platform"]
  }

  resource_type_filter = ["ec2:instance"]
}
```

---

## 3. State in AWS Storage

### S3 Backend Setup (Bootstrap)

These resources must be created **before** configuring the backend. Use a one-time bootstrap:

```hcl
# bootstrap/main.tf - run once, then never modify
provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "mycompany-terraform-state"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name      = "Terraform State"
    ManagedBy = "manual"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-state-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name      = "Terraform State Locks"
    ManagedBy = "manual"
  }
}
```

```bash
cd bootstrap
terraform init
terraform apply
```

Then in your actual project:

```hcl
terraform {
  backend "s3" {
    bucket         = "mycompany-terraform-state"
    key            = "prod/network/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}
```

---

## 4. Deploy a Lambda Function

### Project Structure

```
lambda-lab/
  main.tf
  variables.tf
  outputs.tf
  lambda/
    index.py
```

### Lambda Source Code

**lambda/index.py:**

```python
import json
import os

def handler(event, context):
    environment = os.environ.get('ENVIRONMENT', 'unknown')
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'message': f'Hello from Lambda in {environment}!',
            'event': event
        })
    }
```

### Terraform Configuration

**main.tf:**

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# --- IAM Role for Lambda ---
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --- Package Lambda Code ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# --- Lambda Function ---
resource "aws_lambda_function" "this" {
  function_name    = var.function_name
  description      = "Demo Lambda function deployed via Terraform"
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT = var.environment
      LOG_LEVEL   = "INFO"
    }
  }

  tags = {
    Name        = var.function_name
    Environment = var.environment
  }
}

# --- CloudWatch Log Group ---
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 14
}

# --- Lambda Function URL (public HTTP endpoint) ---
resource "aws_lambda_function_url" "this" {
  function_name      = aws_lambda_function.this.function_name
  authorization_type = "NONE"
}
```

**variables.tf:**

```hcl
variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "hello-terraform"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}
```

**outputs.tf:**

```hcl
output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "function_arn" {
  value = aws_lambda_function.this.arn
}

output "function_url" {
  description = "Public URL to invoke the Lambda"
  value       = aws_lambda_function_url.this.function_url
}

output "log_group" {
  value = aws_cloudwatch_log_group.lambda.name
}
```

### Deploy and Test

```bash
mkdir -p ~/lambda-lab/lambda && cd ~/lambda-lab

# (Create the files above)

terraform init
terraform apply -auto-approve
```

Expected output:
```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

function_arn  = "arn:aws:lambda:us-east-1:123456789012:function:hello-terraform"
function_name = "hello-terraform"
function_url  = "https://abc123def456.lambda-url.us-east-1.on.aws/"
log_group     = "/aws/lambda/hello-terraform"
```

Test the function:
```bash
# Via Function URL
curl $(terraform output -raw function_url)

# Via AWS CLI
aws lambda invoke \
  --function-name hello-terraform \
  --payload '{"key": "value"}' \
  response.json && cat response.json
```

Expected:
```json
{"statusCode": 200, "body": "{\"message\": \"Hello from Lambda in dev!\", \"event\": {\"key\": \"value\"}}"}
```

---

## 5. Compliance Testing with tfsec

### Install tfsec

```bash
# Linux
curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash

# macOS
brew install tfsec

# Verify
tfsec --version
```

### Run a Scan

```bash
cd ~/lambda-lab
tfsec .
```

Expected output:
```
Result #1 HIGH Lambda function URL has no authorization
─────────────────────────────────────────────────
  main.tf:80
─────────────────────────────────────────────────
   78 | resource "aws_lambda_function_url" "this" {
   79 |   function_name      = aws_lambda_function.this.function_name
   80 |   authorization_type = "NONE"
   81 | }
─────────────────────────────────────────────────

  Impact:     Anyone can invoke the Lambda function via the URL
  Resolution: Set authorization_type to "AWS_IAM" and configure IAM auth

  See https://tfsec.dev/docs/aws/lambda/no-public-access

Results: 1 high, 0 medium, 0 low (1 total)
```

### tfsec with Custom Rules

```bash
# Output as JSON
tfsec . --format json > tfsec-results.json

# Exclude specific checks
tfsec . --exclude-path .terraform --exclude aws-lambda-no-public-access

# Run only specific severity
tfsec . --minimum-severity HIGH

# Generate JUnit XML (for CI/CD)
tfsec . --format junit > tfsec-junit.xml
```

### Common tfsec Findings and Fixes

| Finding | Severity | Fix |
|---------|----------|-----|
| S3 bucket without encryption | HIGH | Add `server_side_encryption_configuration` |
| Security group with 0.0.0.0/0 | HIGH | Restrict CIDR blocks |
| RDS without encryption | HIGH | Set `storage_encrypted = true` |
| CloudWatch logs unencrypted | LOW | Add KMS key to log group |
| Lambda public URL | HIGH | Set `authorization_type = "AWS_IAM"` |

### Checkov (Alternative Scanner)

```bash
# Install
pip install checkov

# Run
checkov -d . --framework terraform

# Output
checkov -d . --output json > checkov-results.json
```

---

## 6. Integration Testing with Terratest

Terratest is a Go library for testing Terraform code by actually deploying infrastructure.

### Conceptual Example

```go
// test/lambda_test.go
package test

import (
    "testing"
    "time"

    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/gruntwork-io/terratest/modules/http-helper"
    "github.com/stretchr/testify/assert"
)

func TestLambdaFunction(t *testing.T) {
    t.Parallel()

    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../",
        Vars: map[string]interface{}{
            "function_name": "test-hello-terraform",
            "environment":   "test",
        },
    })

    // Clean up after test
    defer terraform.Destroy(t, terraformOptions)

    // Deploy
    terraform.InitAndApply(t, terraformOptions)

    // Get outputs
    functionURL := terraform.Output(t, terraformOptions, "function_url")
    functionName := terraform.Output(t, terraformOptions, "function_name")

    // Verify outputs
    assert.Equal(t, "test-hello-terraform", functionName)
    assert.Contains(t, functionURL, "lambda-url")

    // Test HTTP endpoint
    http_helper.HttpGetWithRetry(
        t, functionURL, nil, 200,
        `"message"`, 10, 5*time.Second,
    )
}
```

```bash
# Run the test
cd test
go test -v -timeout 30m
```

---

## 7. Troubleshooting Common AWS Provider Errors

### Error: Access Denied

```
Error: error creating EC2 Instance: UnauthorizedOperation:
  You are not authorized to perform this operation.
```

**Debug steps:**
```bash
# 1. Check who you are
aws sts get-caller-identity

# 2. Check if the IAM policy allows the action
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/my-role \
  --action-names ec2:RunInstances

# 3. Enable CloudTrail and check for the denied API call
```

### Error: Resource Already Exists

```
Error: error creating S3 Bucket: BucketAlreadyExists
```

**Fix:** Import the existing resource:
```bash
terraform import aws_s3_bucket.my_bucket my-existing-bucket
```

### Error: Rate Limiting / Throttling

```
Error: error describing EC2 Instances: RequestLimitExceeded:
  Request limit exceeded.
```

**Fix:**
```bash
# Reduce parallelism
terraform apply -parallelism=2

# Or add retry configuration in provider
```

```hcl
provider "aws" {
  region = "us-east-1"

  retry_mode  = "adaptive"
  max_retries = 10
}
```

### Error: Eventual Consistency

```
Error: error reading IAM Role Policy: NoSuchEntity
```

AWS IAM is eventually consistent. The role was just created but is not yet readable.

**Fix:** Usually just re-running `terraform apply` works. For code-level fixes:
```hcl
resource "aws_iam_role" "lambda" {
  name               = "my-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_lambda_function" "this" {
  # ...
  role = aws_iam_role.lambda.arn

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}
```

---

## 8. Hands-On: Full Lambda Deployment

### Step 1: Create the Project

```bash
mkdir -p ~/aws-provider-lab/lambda
cd ~/aws-provider-lab
```

### Step 2: Write the Lambda Code

```bash
cat > lambda/index.py << 'PYEOF'
import json
import os
from datetime import datetime

def handler(event, context):
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'message': f'Hello from {os.environ.get("ENVIRONMENT", "unknown")}!',
            'timestamp': datetime.utcnow().isoformat(),
            'function': context.function_name,
            'memory_mb': context.memory_limit_in_mb,
        })
    }
PYEOF
```

### Step 3: Create Terraform Files

(Use the main.tf, variables.tf, outputs.tf from Section 4 above)

### Step 4: Deploy

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

### Step 5: Run tfsec

```bash
tfsec .
```

### Step 6: Test

```bash
# Get the URL
URL=$(terraform output -raw function_url)

# Test it
curl -s "$URL" | python3 -m json.tool
```

### Step 7: Update and Redeploy

```bash
# Modify the Lambda code
echo 'print("updated")' >> lambda/index.py

# The source_code_hash will detect the change
terraform plan
# Shows: ~ source_code_hash = "old..." -> "new..."

terraform apply -auto-approve
```

### Step 8: Clean Up

```bash
terraform destroy -auto-approve
```

---

## Summary

| Topic | Key Takeaway |
|-------|-------------|
| Authentication | Use OIDC for CI/CD, instance profiles for EC2, never static keys in code |
| Tagging | Use `default_tags` at provider level, enforce with policies |
| State storage | S3 + DynamoDB with versioning and encryption |
| Lambda | `archive_file` for packaging, `source_code_hash` for change detection |
| tfsec | Scan every PR, fix HIGH severity before merge |
| Terratest | Deploy, test, destroy --- real infrastructure validation |
| Troubleshooting | Check identity, IAM, rate limits, eventual consistency |

> **Key takeaway:** The AWS provider is powerful but requires careful attention to authentication, tagging, compliance, and error handling. Automate compliance checks with tfsec/checkov in CI/CD, and use `default_tags` to ensure every resource is properly tagged.
