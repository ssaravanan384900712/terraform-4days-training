# Hands-On 4.3 — Terraform Security Best Practices

**File:** `~/lab4.3-security/`

---

## Concept

Terraform manages your most sensitive infrastructure. A misconfigured Terraform setup can expose secrets in state files, grant overly permissive access, or allow shell injection through provisioners. This lab covers every layer of the security surface: state encryption, secret management, IAM scoping, and provisioner hardening.

### Terraform Security Surface

```
  +-------------------------------------------------------------------+
  |                     ATTACK SURFACE MAP                            |
  +-------------------------------------------------------------------+
  |                                                                   |
  |  STATE FILE          CREDENTIALS        PROVISIONERS              |
  |  +-------------+     +-------------+    +-------------------+     |
  |  | Plaintext   |     | AWS keys in |    | local-exec with   |     |
  |  | secrets in  |     | env vars or |    | user input =      |     |
  |  | tfstate     |     | tfvars      |    | SHELL INJECTION   |     |
  |  +------+------+     +------+------+    +--------+----------+     |
  |         |                   |                    |                |
  |         v                   v                    v                |
  |  ENCRYPT state       USE IAM roles        NEVER interpolate      |
  |  + remote backend    + SSM/Secrets Mgr    user input in shell    |
  |  + KMS               + Vault                                     |
  +-------------------------------------------------------------------+
```

### Security Checklist

| # | Risk | Mitigation |
|---|------|------------|
| 1 | Secrets in state | `sensitive` flag, remote state, encryption |
| 2 | Over-privileged IAM | Least-privilege policy for Terraform runner |
| 3 | State file unencrypted | S3 SSE-KMS, DynamoDB encryption |
| 4 | Secrets in plan output | `sensitive` variables, redacted outputs |
| 5 | Shell injection | Environment variables instead of inline interpolation |
| 6 | Untrusted external data | Validate/sandbox external data sources |
| 7 | Static secrets in code | SSM Parameter Store, Secrets Manager |
| 8 | Secret sprawl | Dynamic secrets with Vault |

---

## Part 1 — Removing Secrets from State

### The Problem

```bash
# After creating an RDS instance, the state file contains:
cat terraform.tfstate | grep -A2 "password"
#   "password": "SuperSecret123!"     <-- PLAINTEXT!
```

### The `sensitive` Flag

```hcl
# variables.tf

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true   # <-- Redacts from plan/apply output
}
```

```hcl
# main.tf

resource "aws_db_instance" "main" {
  identifier     = "mydb"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"
  db_name        = "myapp"
  username       = "admin"
  password       = var.db_password   # marked sensitive
  # ...
}

output "db_endpoint" {
  value = aws_db_instance.main.endpoint
}

output "db_password" {
  value     = var.db_password
  sensitive = true   # REQUIRED when output references sensitive var
}
```

```bash
terraform plan -var='db_password=SuperSecret123!'
```

Expected output:
```
  # aws_db_instance.main will be created
  + resource "aws_db_instance" "main" {
      + password = (sensitive value)     # <-- Redacted!
    }
```

> **Warning:** The `sensitive` flag only redacts CLI output. The secret is STILL in the state file in plaintext. You MUST encrypt the state file.

---

## Part 2 — Least-Privileged IAM for Terraform

### Full IAM Policy for Terraform Runner

This policy grants only what Terraform needs for a typical VPC + EC2 + S3 workload.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformStateAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::mycompany-terraform-state",
        "arn:aws:s3:::mycompany-terraform-state/*"
      ]
    },
    {
      "Sid": "TerraformStateLocking",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:us-east-1:ACCOUNT_ID:table/terraform-locks"
    },
    {
      "Sid": "EC2Management",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupEgress"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Sid": "VPCManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc",
        "ec2:DeleteVpc",
        "ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet",
        "ec2:DeleteSubnet",
        "ec2:CreateInternetGateway",
        "ec2:DeleteInternetGateway",
        "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway",
        "ec2:CreateRouteTable",
        "ec2:DeleteRouteTable",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Sid": "KMSForStateEncryption",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ],
      "Resource": "arn:aws:kms:us-east-1:ACCOUNT_ID:key/KEY_ID"
    }
  ]
}
```

```bash
# Create the policy
aws iam create-policy \
  --policy-name TerraformRunner \
  --policy-document file://terraform-runner-policy.json

# Attach to a role (for CI/CD) or user (for local dev)
aws iam attach-role-policy \
  --role-name terraform-ci-role \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/TerraformRunner
```

> **Tip:** Start with broader permissions during initial development, then use AWS Access Analyzer to generate a policy based on actual usage: `aws accessanalyzer generate-policy --arn arn:aws:iam::ACCOUNT_ID:role/terraform-ci-role`

---

## Part 3 — Encryption at Rest (State File KMS)

### Step 1: Create a KMS key for state encryption

```bash
mkdir -p ~/lab4.3-security/kms-demo && cd ~/lab4.3-security/kms-demo
```

```hcl
# kms.tf -- Create KMS key for Terraform state encryption

provider "aws" {
  region = "us-east-1"
}

resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "TerraformAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/terraform-ci-role"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Purpose   = "terraform-state-encryption"
    ManagedBy = "terraform"
  }
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}

data "aws_caller_identity" "current" {}

output "kms_key_arn" {
  value = aws_kms_key.terraform_state.arn
}
```

### Step 2: S3 bucket with KMS encryption

```hcl
# state-bucket.tf

resource "aws_s3_bucket" "terraform_state" {
  bucket = "mycompany-terraform-state-${data.aws_caller_identity.current.account_id}"

  tags = {
    Purpose   = "terraform-state"
    ManagedBy = "terraform"
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
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    bucket_key_enabled = true
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
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Purpose   = "terraform-state-locking"
    ManagedBy = "terraform"
  }
}
```

### Step 3: Backend config using KMS-encrypted bucket

```hcl
# backend.tf -- Use in your project

terraform {
  backend "s3" {
    bucket         = "mycompany-terraform-state-123456789012"
    key            = "prod/infrastructure.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
    kms_key_id     = "alias/terraform-state"
  }
}
```

---

## Part 4 — Securing Plan Output (Logs)

### The Problem

```bash
# CI/CD logs can leak sensitive values
terraform plan 2>&1 | tee plan-output.log
# If a variable is not marked sensitive, it appears in the log!
```

### The Fix

```hcl
# Always mark sensitive variables
variable "api_key" {
  type      = string
  sensitive = true
}

# Sensitive outputs
output "api_key" {
  value     = var.api_key
  sensitive = true
}
```

```bash
# In CI/CD, use plan files instead of text output
terraform plan -out=tfplan          # Binary file, not readable
terraform show -json tfplan | jq    # Structured, can be filtered

# Strip sensitive data from JSON plan
terraform show -json tfplan | \
  jq 'del(.planned_values.outputs[].value)' > safe-plan.json
```

---

## Part 5 — local-exec Dangers: Shell Injection

### The Vulnerability (DO NOT use this pattern)

```hcl
# DANGEROUS -- Shell injection via user input!

variable "instance_name" {
  type = string
}

resource "null_resource" "configure" {
  provisioner "local-exec" {
    # If instance_name = "test; rm -rf /" this executes the rm command!
    command = "echo 'Configuring ${var.instance_name}' >> /tmp/setup.log"
  }
}
```

### Demonstration of the Attack

```bash
mkdir -p ~/lab4.3-security/injection-demo && cd ~/lab4.3-security/injection-demo
```

```hcl
# main.tf -- VULNERABLE version (for demonstration only)

variable "server_name" {
  type    = string
  default = "web-server"
}

resource "null_resource" "demo_vulnerable" {
  provisioner "local-exec" {
    command = "echo 'Setting up ${var.server_name}' > /tmp/tf-injection-test.txt"
  }
}
```

```bash
terraform init

# Normal use
terraform apply -var='server_name=web-01' -auto-approve
cat /tmp/tf-injection-test.txt
# Output: Setting up web-01

# ATTACK: inject a command
terraform apply -var="server_name=web-01' && echo 'INJECTED" -auto-approve
cat /tmp/tf-injection-test.txt
# Output: Setting up web-01
# PLUS the injected command ran!
```

### The Fix: Use Environment Variables

```hcl
# main.tf -- SAFE version

variable "server_name" {
  type    = string
  default = "web-server"
}

resource "null_resource" "demo_safe" {
  provisioner "local-exec" {
    # Pass data through environment variables -- NOT string interpolation
    command = "echo \"Setting up $SERVER_NAME\" > /tmp/tf-injection-test.txt"

    environment = {
      SERVER_NAME = var.server_name    # Safe: not interpreted by shell
    }
  }
}
```

```bash
# The attack no longer works
terraform apply -var="server_name=web-01' && echo 'INJECTED" -auto-approve
cat /tmp/tf-injection-test.txt
# Output: Setting up web-01' && echo 'INJECTED
# The payload is treated as a literal string, not a command
```

> **Rule:** NEVER use `${var.xxx}` inside `command` strings of local-exec or remote-exec. ALWAYS use the `environment` block.

---

## Part 6 — External Data Source Dangers

### The Risk

```hcl
# external data source runs an ARBITRARY SCRIPT
data "external" "lookup" {
  program = ["python3", "${path.module}/scripts/lookup.py"]

  query = {
    environment = var.environment
  }
}
```

If `lookup.py` is compromised or untrusted, it can:
- Exfiltrate credentials from environment variables
- Modify files on the CI/CD runner
- Make network calls to external services

### Mitigations

| Mitigation | How |
|-----------|-----|
| Pin script versions | Commit scripts to repo, review changes |
| Use data sources instead | AWS data sources are safer than shell scripts |
| Sandbox execution | Run Terraform in a container with limited access |
| Audit `external` usage | Grep for `data "external"` in code reviews |

---

## Part 7 — Static Secrets: AWS SSM Parameter Store

### Step 4: Create SSM Parameters

```bash
mkdir -p ~/lab4.3-security/ssm-demo && cd ~/lab4.3-security/ssm-demo

# Create a secret in SSM Parameter Store
aws ssm put-parameter \
  --name "/myapp/dev/db_password" \
  --value "MySecurePassword123!" \
  --type "SecureString" \
  --description "Database password for dev environment"

# Create a plain-text config parameter
aws ssm put-parameter \
  --name "/myapp/dev/db_host" \
  --value "mydb.cluster-abc123.us-east-1.rds.amazonaws.com" \
  --type "String" \
  --description "Database host for dev environment"

# Verify
aws ssm get-parameter --name "/myapp/dev/db_password" --with-decryption
```

### Step 5: Read SSM in Terraform

```hcl
# main.tf

provider "aws" {
  region = "us-east-1"
}

# Read a SecureString parameter
data "aws_ssm_parameter" "db_password" {
  name            = "/myapp/dev/db_password"
  with_decryption = true
}

# Read a String parameter
data "aws_ssm_parameter" "db_host" {
  name = "/myapp/dev/db_host"
}

# Use in resources
resource "aws_db_instance" "main" {
  identifier     = "mydb"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"
  db_name        = "myapp"
  username       = "admin"
  password       = data.aws_ssm_parameter.db_password.value

  tags = {
    Environment = "dev"
  }
}

output "db_host" {
  value = data.aws_ssm_parameter.db_host.value
}

output "db_password_notice" {
  value = "Password retrieved from SSM (not shown)"
}
```

```bash
terraform init
terraform plan
```

Expected output:
```
  # aws_db_instance.main will be created
  + resource "aws_db_instance" "main" {
      + password = (sensitive value)
    }
```

### AWS Secrets Manager Alternative

```hcl
# For more complex secrets (JSON, rotation)
data "aws_secretsmanager_secret_version" "db_creds" {
  secret_id = "myapp/dev/db-credentials"
}

locals {
  db_creds = jsondecode(data.aws_secretsmanager_secret_version.db_creds.secret_string)
}

# Use: local.db_creds.username, local.db_creds.password
```

---

## Part 8 — Dynamic Secrets: HashiCorp Vault

### Vault Integration Overview

```
  +------------------+        +------------------+        +------------------+
  |   Terraform      |  auth  |   HashiCorp      | create |   AWS            |
  |   requests       |------->|   Vault          |------->|   STS            |
  |   DB creds       |        |   generates      |        |   temp creds     |
  +------------------+        |   short-lived    |        +------------------+
                              |   credentials    |
                              +------------------+
                                     |
                           Auto-revoke after TTL
```

```hcl
# Vault provider configuration
provider "vault" {
  address = "https://vault.mycompany.com:8200"
  # Auth via VAULT_TOKEN env var or AppRole
}

# Read dynamic database credentials
data "vault_generic_secret" "db_creds" {
  path = "database/creds/myapp-role"
}

# Credentials are dynamic -- new ones generated each run
# Auto-expire after the configured TTL (e.g., 1 hour)
resource "aws_db_instance" "main" {
  username = data.vault_generic_secret.db_creds.data["username"]
  password = data.vault_generic_secret.db_creds.data["password"]
  # ...
}
```

> **Key Advantage:** Dynamic secrets are generated on demand and automatically revoked. There is nothing to leak because the secret only exists for the duration of the Terraform run.

---

## Hands-On Cleanup

```bash
# Remove SSM parameters
aws ssm delete-parameter --name "/myapp/dev/db_password"
aws ssm delete-parameter --name "/myapp/dev/db_host"

# Remove test files
rm -f /tmp/tf-injection-test.txt

# Destroy any created resources
cd ~/lab4.3-security/kms-demo && terraform destroy -auto-approve
cd ~/lab4.3-security/injection-demo && terraform destroy -auto-approve
```

---

## Summary

| Security Layer | Threat | Solution |
|---------------|--------|----------|
| State file | Plaintext secrets | S3 + KMS encryption, `sensitive` flag |
| IAM | Over-privileged runner | Scoped policy per workload |
| Plan output | Secrets in CI logs | `sensitive` vars, binary plan files |
| Provisioners | Shell injection | Environment variables, never interpolate |
| External data | Untrusted scripts | Pin versions, prefer native data sources |
| Static secrets | Secrets in code/tfvars | SSM Parameter Store, Secrets Manager |
| Dynamic secrets | Long-lived credentials | HashiCorp Vault, short TTLs |
