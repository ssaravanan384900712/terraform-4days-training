# Hands-On 1.2e — AWS Account & Provider Setup

**Directory:** `~/terraform-labs/lab-aws-setup/`

---

## Concept

Before deploying AWS resources with Terraform, you need:
1. An AWS account with an IAM user
2. Access keys for programmatic access
3. AWS CLI configured
4. The AWS provider configured in Terraform

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  You (local) │────►│  Terraform   │────►│  AWS API     │
│              │     │  + AWS       │     │              │
│  aws creds   │     │  Provider    │     │  Creates EC2,│
│  in ~/.aws/  │     │  (plugin)    │     │  S3, VPC...  │
└──────────────┘     └──────────────┘     └──────────────┘
```

---

## 1. Create an IAM User for Terraform

### Step 1 — Log into the AWS Console

Go to https://console.aws.amazon.com and log in as root or an admin user.

### Step 2 — Create a dedicated IAM user

1. Navigate to **IAM → Users → Create user**
2. **User name:** `terraform-lab-user`
3. Click **Next: Permissions**
4. Select **Attach policies directly**
5. Attach: `AdministratorAccess`
6. Click **Next → Create user**

> ⚠️ `AdministratorAccess` is for training only. In production, use least-privilege policies (covered in Day 4).

### Step 3 — Create access keys

1. Go to **IAM → Users → terraform-lab-user → Security credentials**
2. Under **Access keys**, click **Create access key**
3. Select **Command Line Interface (CLI)**
4. Check the acknowledgment box → **Next → Create access key**
5. **Save both values immediately** — the Secret is shown only once:

```
Access Key ID:     AKIAIOSFODNN7EXAMPLE
Secret Access Key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

> **Never commit these to Git. Never share them. Rotate immediately if compromised.**

---

## 2. Install and Configure AWS CLI

### Step 1 — Install AWS CLI v2

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### Step 2 — Verify

```bash
aws --version
```

```
aws-cli/2.15.x Python/3.11.x Linux/6.x.x
```

### Step 3 — Configure credentials

```bash
aws configure
```

Enter your values:

```
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]: us-east-1
Default output format [None]: json
```

### Step 4 — Verify connectivity

```bash
aws sts get-caller-identity
```

**Expected output:**

```json
{
    "UserId": "AIDAIOSFODNN7EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/terraform-lab-user"
}
```

> If this fails, double-check your access keys and region.

### What `aws configure` created

```bash
cat ~/.aws/credentials
```

```ini
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

```bash
cat ~/.aws/config
```

```ini
[default]
region = us-east-1
output = json
```

---

## 3. AWS Provider Authentication Methods

Terraform supports multiple ways to supply AWS credentials. It checks them in this order:

```
Priority (highest to lowest):
──────────────────────────────────────────
1. Static credentials in provider block    ← ❌ Never use
2. Environment variables                   ← ✅ Good for CI/CD
3. Shared credentials file (~/.aws/)       ← ✅ Good for local dev
4. Container credentials (ECS task role)   ← ✅ Good for containers
5. Instance profile (EC2 IAM role)         ← ✅ Best for production
```

### Method 1: Static Credentials ❌

```hcl
provider "aws" {
  region     = "us-east-1"
  access_key = "AKIA..."
  secret_key = "wJal..."
}
```

> ❌ **NEVER do this.** Credentials end up in Git history forever.

### Method 2: Environment Variables ✅

```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="wJal..."
export AWS_DEFAULT_REGION="us-east-1"
```

```hcl
provider "aws" {
  region = "us-east-1"
  # Credentials auto-discovered from env
}
```

> ✅ Good for CI/CD pipelines (GitHub Actions, Jenkins).

### Method 3: Shared Credentials File ✅ (What we're using)

Already configured by `aws configure`. Terraform reads `~/.aws/credentials` automatically:

```hcl
provider "aws" {
  region = "us-east-1"
  # Credentials auto-discovered from ~/.aws/credentials
}
```

For named profiles:

```hcl
provider "aws" {
  region  = "us-east-1"
  profile = "terraform-lab"
}
```

### Method 4: IAM Instance Profile ✅✅ (Best for production)

When running on EC2, attach an IAM Role. No credentials needed in code at all:

```hcl
provider "aws" {
  region = "us-east-1"
  # Auto-discovers from EC2 instance metadata
}
```

### Method 5: Assume Role (Cross-account)

```hcl
provider "aws" {
  region = "us-east-1"
  assume_role {
    role_arn     = "arn:aws:iam::ACCOUNT_ID:role/TerraformRole"
    session_name = "terraform-session"
  }
}
```

---

## 4. Hands-On: First AWS Resource

### Step 1 — Create project directory

```bash
mkdir -p ~/terraform-labs/lab-aws-setup
cd ~/terraform-labs/lab-aws-setup
```

### Step 2 — Write providers.tf

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = "lab"
      ManagedBy   = "terraform"
      Project     = "terraform-training"
    }
  }
}
```

> **`default_tags`** automatically tags every AWS resource Terraform creates. Great for cost tracking.

### Step 3 — Write main.tf

```hcl
resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "test" {
  bucket = "tf-lab-test-${random_id.suffix.hex}"
}

output "bucket_name" {
  value = aws_s3_bucket.test.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.test.arn
}
```

### Step 4 — Initialize

```bash
terraform init
```

**Expected output:**

```
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Finding hashicorp/random versions matching "~> 3.0"...
- Installing hashicorp/aws v5.72.0...
- Installing hashicorp/random v3.6.3...

Terraform has been successfully initialized!
```

> The AWS provider is ~400MB. First `init` takes a minute.

### Step 5 — Plan

```bash
terraform plan
```

```
  # random_id.suffix will be created
  + resource "random_id" "suffix" { ... }

  # aws_s3_bucket.test will be created
  + resource "aws_s3_bucket" "test" {
      + bucket = (known after apply)
      + arn    = (known after apply)
      ...
    }

Plan: 2 to add, 0 to change, 0 to destroy.
```

### Step 6 — Apply

```bash
terraform apply
```

Type `yes`. **Expected output:**

```
random_id.suffix: Creating...
random_id.suffix: Creation complete [id=x1y2z3]
aws_s3_bucket.test: Creating...
aws_s3_bucket.test: Creation complete after 3s [id=tf-lab-test-a1b2c3d4]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:
bucket_arn  = "arn:aws:s3:::tf-lab-test-a1b2c3d4"
bucket_name = "tf-lab-test-a1b2c3d4"
```

### Step 7 — Verify in AWS

```bash
aws s3 ls | grep tf-lab-test
```

```
2024-01-15 10:30:00 tf-lab-test-a1b2c3d4
```

```bash
# Check the tags
aws s3api get-bucket-tagging --bucket $(terraform output -raw bucket_name)
```

```json
{
    "TagSet": [
        { "Key": "Environment", "Value": "lab" },
        { "Key": "ManagedBy", "Value": "terraform" },
        { "Key": "Project", "Value": "terraform-training" }
    ]
}
```

> Notice the `default_tags` were applied automatically!

### Step 8 — Clean up

```bash
terraform destroy
```

Type `yes`. Bucket is deleted.

```bash
aws s3 ls | grep tf-lab-test
# (no output — bucket is gone)
```

---

## 5. Provider Version Constraints

Always pin versions to avoid surprises:

| Constraint | Meaning | Example |
|-----------|---------|---------|
| `= 5.31.0` | Exact version | Only 5.31.0 |
| `>= 5.0` | Minimum version | 5.0 or newer |
| `~> 5.0` | Pessimistic (recommended) | Any 5.x but not 6.x |
| `>= 5.0, < 5.50` | Range | Between 5.0 and 5.49 |

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"    # ← Use this in most cases
    }
  }
}
```

### Upgrading providers

```bash
# Check current versions
terraform providers

# Upgrade to latest within constraints
terraform init -upgrade
```

---

## 6. Provider Aliases (Multi-Region)

Deploy to multiple regions from the same config:

```hcl
provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "west"
  region = "us-west-2"
}

resource "aws_s3_bucket" "east" {
  bucket = "my-app-east-${random_id.suffix.hex}"
}

resource "aws_s3_bucket" "west" {
  provider = aws.west
  bucket   = "my-app-west-${random_id.suffix.hex}"
}
```

> Resources without `provider` use the default (no alias). Resources with `provider = aws.west` use the aliased provider.

---

## Summary

| Task | Status |
|------|--------|
| IAM user created with access keys | ✅ |
| AWS CLI installed and configured | ✅ |
| `aws sts get-caller-identity` works | ✅ |
| AWS provider authentication understood | ✅ |
| First S3 bucket created and destroyed | ✅ |
| default_tags verified | ✅ |
| Provider versioning understood | ✅ |

> **Next:** Proceed to **Hands-On 1.3** to deploy your first EC2 instance with security groups and user_data!
