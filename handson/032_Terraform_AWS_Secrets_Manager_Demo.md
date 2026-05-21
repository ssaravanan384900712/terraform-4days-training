# 032 — Terraform AWS Secrets Manager Demo

**By: Saravanan Sundaramoorthy**
**Environment:** AWS ap-south-1 (Mumbai)
**Time to complete:** ~10 minutes

---

## Topic

| Concept | What it means |
|---------|--------------|
| **aws_secretsmanager_secret** | Creates the secret container (name, description, tags) |
| **aws_secretsmanager_secret_version** | Stores the actual secret value inside the container |
| **jsonencode()** | Terraform built-in that serialises a map to a valid JSON string |
| **recovery_window_in_days** | How many days before a deleted secret is truly gone — set `0` to allow immediate deletion in labs |
| **Secret rotation** | Change the `secret_string` in Terraform and re-apply; Secrets Manager stores previous versions automatically |
| **Never hardcode passwords** | Use `sensitive = true` variables, env vars, or existing Secrets Manager secrets as the source of truth |

AWS Secrets Manager stores credentials, API keys, and configuration strings securely. Applications retrieve them at runtime without embedding secrets in source code. This lab stores a JSON blob of database credentials, verifies the value with the AWS CLI, and then destroys everything cleanly.

---

## Architecture

```
                         ap-south-1
  ┌────────────────────────────────────────────────────────┐
  │                                                        │
  │   AWS Secrets Manager                                  │
  │  ┌──────────────────────────────────────────────────┐  │
  │  │                                                  │  │
  │  │  aws_secretsmanager_secret                       │  │
  │  │  name: terraform-032-robochef-db-<suffix>        │  │
  │  │  recovery_window_in_days: 0  (demo)              │  │
  │  │                                                  │  │
  │  │  ┌────────────────────────────────────────────┐  │  │
  │  │  │ aws_secretsmanager_secret_version           │  │  │
  │  │  │ {                                           │  │  │
  │  │  │   "username": "robochef",                   │  │  │
  │  │  │   "password": "Robochef2024!",              │  │  │
  │  │  │   "host":     "robochef-rds.ap-south-1...", │  │  │
  │  │  │   "dbname":   "robochefdb"                  │  │  │
  │  │  │ }                                           │  │  │
  │  │  └────────────────────────────────────────────┘  │  │
  │  └──────────────────────────────────────────────────┘  │
  │                                                        │
  └────────────────────────────────────────────────────────┘
            │
            │  aws secretsmanager get-secret-value
            │
       Your app / AWS CLI / Lambda
```

---

## What Terraform Creates

| # | Resource | Name | Purpose |
|---|----------|------|---------|
| 1 | `random_string.suffix` | 6-char suffix | Makes secret name unique so re-runs do not collide |
| 2 | `aws_secretsmanager_secret.robochef_db` | terraform-032-robochef-db-`<suffix>` | The secret container with metadata and tags |
| 3 | `aws_secretsmanager_secret_version.robochef_db` | (tied to secret above) | Stores the JSON credentials string as the current version |

---

## Step 1 — Create the project directory

```bash
mkdir ~/terraform-aws-032-secrets && cd ~/terraform-aws-032-secrets
```

---

## Step 2 — Write the Terraform files

### providers.tf

```bash
cat > providers.tf <<'EOF_TF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
EOF_TF
```

### variables.tf

```bash
cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "db_password" {
  description = "Database password to store in Secrets Manager"
  type        = string
  sensitive   = true
  default     = "Robochef2024!"
  # WARNING: Never use a hardcoded default password in production.
  # Supply via:  export TF_VAR_db_password="YourRealPassword"
}
EOF_TF
```

### main.tf

```bash
cat > main.tf <<'EOF_TF'
# ── Random suffix: prevents name collision across destroy/re-apply ─────────────
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# ── Secret container ──────────────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "robochef_db" {
  name        = "terraform-032-robochef-db-${random_string.suffix.result}"
  description = "Database credentials for robochef.co application"

  # Set to 0 so terraform destroy can delete immediately in labs.
  # In production, use 7 (minimum) to 30 days to allow recovery.
  recovery_window_in_days = 0

  tags = {
    Name    = "robochef-db-secret"
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}

# ── Secret version: the actual credentials stored as JSON ─────────────────────
resource "aws_secretsmanager_secret_version" "robochef_db" {
  secret_id = aws_secretsmanager_secret.robochef_db.id

  secret_string = jsonencode({
    username = "robochef"
    password = var.db_password
    host     = "robochef-rds.ap-south-1.rds.amazonaws.com"
    dbname   = "robochefdb"
  })
}
EOF_TF
```

### outputs.tf

```bash
cat > outputs.tf <<'EOF_TF'
output "secret_arn" {
  description = "ARN of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.robochef_db.arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.robochef_db.name
}

output "get_secret_cmd" {
  description = "AWS CLI command to retrieve and pretty-print the secret"
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.robochef_db.name} --region ${var.aws_region} --query SecretString --output text | python3 -m json.tool"
}
EOF_TF
```

---

## Step 3 — Init, Format, Validate, Plan

```bash
terraform init
```

Expected output:
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Finding hashicorp/random versions matching "~> 3.0"...
- Installed hashicorp/aws v6.x.x
- Installed hashicorp/random v3.x.x
Terraform has been successfully initialized!
```

```bash
terraform fmt
terraform validate
```

Expected:
```
Success! The configuration is valid.
```

```bash
terraform plan
```

Expected summary:
```
Plan: 3 to add, 0 to change, 0 to destroy.
```

The 3 resources:
- `random_string.suffix`
- `aws_secretsmanager_secret.robochef_db`
- `aws_secretsmanager_secret_version.robochef_db`

---

## Step 4 — Apply

```bash
terraform apply -auto-approve
```

Expected output:
```
random_string.suffix: Creating...
random_string.suffix: Creation complete after 0s [id=powwf1]
aws_secretsmanager_secret.robochef_db: Creating...
aws_secretsmanager_secret.robochef_db: Creation complete after 1s [id=arn:aws:secretsmanager:ap-south-1:043000359118:secret:terraform-032-robochef-db-powwf1-o4YRy5]
aws_secretsmanager_secret_version.robochef_db: Creating...
aws_secretsmanager_secret_version.robochef_db: Creation complete after 0s

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

secret_arn     = "arn:aws:secretsmanager:ap-south-1:043000359118:secret:terraform-032-robochef-db-powwf1-o4YRy5"
secret_name    = "terraform-032-robochef-db-powwf1"
get_secret_cmd = "aws secretsmanager get-secret-value --secret-id terraform-032-robochef-db-powwf1 --region ap-south-1 --query SecretString --output text | python3 -m json.tool"
```

---

## Step 5 — Verify with AWS CLI

Copy the `get_secret_cmd` output and run it, or use the command below with your actual secret name:

```bash
SECRET_NAME=$(terraform output -raw secret_name)

aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --region ap-south-1 \
  --query SecretString \
  --output text | python3 -m json.tool
```

Live result:
```json
{
    "dbname": "robochefdb",
    "host": "robochef-rds.ap-south-1.rds.amazonaws.com",
    "password": "Robochef2024!",
    "username": "robochef"
}
```

You can also view the secret in the AWS console:
1. Open **AWS Console** → **Secrets Manager**
2. Find `terraform-032-robochef-db-<suffix>`
3. Click **Retrieve secret value**

---

## Key Concepts

### recovery_window_in_days = 0

| Value | Behaviour |
|-------|-----------|
| `0` | Secret is deleted immediately when `terraform destroy` runs. Use in labs only. |
| `7`–`30` | AWS holds the secret in a recoverable state for the given number of days. Production default is 30. |

> In production, always use `recovery_window_in_days = 30` (or at least 7).
> A deleted secret with a recovery window can be restored; one deleted with `0`
> cannot.

### jsonencode() for structured secrets

Applications expect credentials as a JSON blob, not a plain string. `jsonencode()` converts a Terraform map into properly-escaped JSON:

```hcl
secret_string = jsonencode({
  username = "robochef"
  password = var.db_password
  host     = "robochef-rds.ap-south-1.rds.amazonaws.com"
  dbname   = "robochefdb"
})
```

This produces:
```json
{"dbname":"robochefdb","host":"robochef-rds.ap-south-1.rds.amazonaws.com","password":"Robochef2024!","username":"robochef"}
```

### Rotating a secret via Terraform

Change the value and re-apply. Secrets Manager automatically stores the old version under the label `AWSPREVIOUS`:

```hcl
# In variables.tf, update the default or supply a new TF_VAR_db_password
```

```bash
terraform apply -auto-approve   # creates a new AWSCURRENT version
```

### Never hardcode passwords

| Approach | Risk |
|----------|------|
| Hardcode in `.tf` file | Ends up in Git history — treat as compromised |
| `default` in `variables.tf` | Still readable in state file — only acceptable in isolated demos |
| `TF_VAR_db_password` env var | Better — not in code, but still in shell history |
| Retrieve from existing Secrets Manager secret via `data` source | Best — credentials never touch Terraform state in plain text |

---

## Step 6 — Destroy and clean up

```bash
terraform destroy -auto-approve
```

Expected output:
```
aws_secretsmanager_secret_version.robochef_db: Destroying...
aws_secretsmanager_secret_version.robochef_db: Destruction complete after 0s
aws_secretsmanager_secret.robochef_db: Destroying...
aws_secretsmanager_secret.robochef_db: Destruction complete after 0s
random_string.suffix: Destroying...
random_string.suffix: Destruction complete after 0s

Destroy complete! Resources: 3 destroyed.
```

Remove local Terraform cache:
```bash
rm -rf .terraform
```

---

## Copy-Paste Script (all steps in one)

```bash
#!/bin/bash
set -e

WORKDIR=~/terraform-aws-032-secrets
mkdir -p "$WORKDIR" && cd "$WORKDIR"

# ── providers.tf ──────────────────────────────────────────────────────────────
cat > providers.tf <<'EOF_TF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
EOF_TF

# ── variables.tf ──────────────────────────────────────────────────────────────
cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "db_password" {
  description = "Database password to store in Secrets Manager"
  type        = string
  sensitive   = true
  default     = "Robochef2024!"
}
EOF_TF

# ── main.tf ───────────────────────────────────────────────────────────────────
cat > main.tf <<'EOF_TF'
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "aws_secretsmanager_secret" "robochef_db" {
  name        = "terraform-032-robochef-db-${random_string.suffix.result}"
  description = "Database credentials for robochef.co application"
  recovery_window_in_days = 0

  tags = {
    Name    = "robochef-db-secret"
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}

resource "aws_secretsmanager_secret_version" "robochef_db" {
  secret_id = aws_secretsmanager_secret.robochef_db.id

  secret_string = jsonencode({
    username = "robochef"
    password = var.db_password
    host     = "robochef-rds.ap-south-1.rds.amazonaws.com"
    dbname   = "robochefdb"
  })
}
EOF_TF

# ── outputs.tf ────────────────────────────────────────────────────────────────
cat > outputs.tf <<'EOF_TF'
output "secret_arn" {
  description = "ARN of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.robochef_db.arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.robochef_db.name
}

output "get_secret_cmd" {
  description = "AWS CLI command to retrieve and pretty-print the secret"
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.robochef_db.name} --region ${var.aws_region} --query SecretString --output text | python3 -m json.tool"
}
EOF_TF

terraform init
terraform fmt
terraform validate
terraform apply -auto-approve

echo ""
echo "=== Verifying secret ==="
SECRET_NAME=$(terraform output -raw secret_name)
aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --region ap-south-1 \
  --query SecretString \
  --output text | python3 -m json.tool

echo ""
echo "=== Destroying ==="
terraform destroy -auto-approve
rm -rf .terraform
echo "Done — all resources destroyed and .terraform removed."
```

---

## Concept Summary

| Concept | Value used | Why |
|---------|-----------|-----|
| Secret name | terraform-032-robochef-db-`<suffix>` | Random suffix prevents name collision on re-create |
| recovery_window_in_days | 0 | Allows immediate destroy in labs; use 7–30 in production |
| jsonencode() | Maps credentials to JSON string | Applications expect a JSON blob, not a plain string |
| sensitive = true | db_password variable | Terraform hides the value from plan/apply terminal output |
| Secret version | AWSCURRENT | Secrets Manager tracks current and previous versions automatically |
| Rotation | Re-apply after changing variable | New version becomes AWSCURRENT; old becomes AWSPREVIOUS |
