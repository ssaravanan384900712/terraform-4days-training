# 018 — Using S3 as Terraform Remote State Backend

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~25 minutes

## Topic

By default Terraform stores state in a local `terraform.tfstate` file. That works on your laptop, but falls apart the moment a second engineer joins the project — they have a different file, conflicts happen, and infrastructure drifts.

**Remote state** moves the state file to a shared, durable store. AWS S3 is the most common choice:

- Single source of truth — everyone reads and writes the same file
- S3 versioning preserves a full history of every state change
- Works with DynamoDB for state locking (not covered in this lab)
- No extra Terraform Cloud account required

### The chicken-and-egg problem

You need an S3 bucket **before** Terraform can use it as a backend. But you want Terraform to manage that bucket. The standard solution is the **bootstrap pattern**:

1. A small, separate `bootstrap/` project creates the S3 bucket using **local state**.
2. Your main project declares an empty `backend "s3" {}` and fills in the bucket name at `terraform init` time via `-backend-config` flags.

This lab follows that real-world two-phase workflow.

---

## What This Lab Creates

```text
Phase 1 — Bootstrap (local state, bootstrap/ folder)
  random_string.suffix          → 8-char suffix for a globally unique bucket name
  aws_s3_bucket.tfstate         → S3 bucket: terraform-018-tfstate-<suffix>
  aws_s3_bucket_versioning      → versioning enabled on the state bucket

Phase 2 — Main project (remote state stored in the bucket above)
  aws_s3_bucket.app             → S3 bucket: terraform-018-app-bucket-demo
```

**Real results from live test:**
- State bucket: `terraform-018-tfstate-lazje1gv`
- App bucket: `terraform-018-app-bucket-demo`
- State file in S3: `018-demo/terraform.tfstate` (2974 bytes)

---

## Project Structure

```text
~/terraform-018-demo/
├── bootstrap/
│   └── main.tf          ← creates the S3 state bucket (local state)
├── providers.tf         ← backend "s3" {} with no hardcoded values
├── variables.tf
└── main.tf              ← creates the demo app bucket (remote state)
```

---

## Prerequisites

- AWS CLI configured (`aws configure` or IAM role on GCE)
- Terraform >= 1.0 installed
- IAM permissions: `s3:CreateBucket`, `s3:PutBucketVersioning`, `s3:GetObject`, `s3:PutObject`, `s3:ListBucket`

```bash
# Verify AWS access
aws sts get-caller-identity
aws configure get region
```

---

## Phase 1 — Bootstrap: Create the State Bucket

### Step 1.1 — Create the project folder

```bash
mkdir -p ~/terraform-018-demo/bootstrap
cd ~/terraform-018-demo
```

### Step 1.2 — Create bootstrap/main.tf

```bash
cat > bootstrap/main.tf <<'EOF_TF'
terraform {
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}

provider "aws" { region = "ap-south-1" }

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "aws_s3_bucket" "tfstate" {
  bucket        = "terraform-018-tfstate-${random_string.suffix.result}"
  force_destroy = true

  tags = { Name = "terraform-018-state-bucket" }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

output "bucket_name" {
  value = aws_s3_bucket.tfstate.bucket
}
EOF_TF
```

**Why `force_destroy = true`?**
Normally Terraform refuses to delete an S3 bucket that contains objects (state files are objects). `force_destroy = true` allows `terraform destroy` to empty and delete the bucket. Appropriate here because this is infrastructure tooling — in a production environment you would remove this flag to add a safety net.

**Why versioning?**
Every `terraform apply` overwrites `terraform.tfstate` in S3. With versioning enabled, S3 keeps every previous version. If a bad apply corrupts state, you can restore an earlier version from the S3 console.

### Step 1.3 — Init and apply the bootstrap project

```bash
cd ~/terraform-018-demo/bootstrap
terraform init
terraform apply
```

Expected output (abbreviated):

```
Terraform will perform the following actions:

  # aws_s3_bucket.tfstate will be created
  # aws_s3_bucket_versioning.tfstate will be created
  # random_string.suffix will be created

Plan: 3 to add, 0 to change, 0 to destroy.

Do you want to perform these actions? yes

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

bucket_name = "terraform-018-tfstate-lazje1gv"
```

### Step 1.4 — Capture the bucket name

```bash
TFSTATE_BUCKET=$(terraform output -raw bucket_name)
echo "State bucket: $TFSTATE_BUCKET"
```

Keep this value — you will pass it to the main project's `terraform init`.

---

## Phase 2 — Main Project: Use the S3 Backend

### Step 2.1 — Create providers.tf

```bash
cd ~/terraform-018-demo

cat > providers.tf <<'EOF_TF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}
EOF_TF
```

**Notice: the `backend "s3" {}` block is intentionally empty.** No bucket name, no key, no region. All of those values are injected at `terraform init` time via `-backend-config` flags. This avoids hardcoding the bucket name in version control and makes the configuration reusable across environments.

### Step 2.2 — Create variables.tf

```bash
cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  type    = string
  default = "ap-south-1"
}
EOF_TF
```

### Step 2.3 — Create main.tf

```bash
cat > main.tf <<'EOF_TF'
resource "aws_s3_bucket" "app" {
  bucket        = "terraform-018-app-bucket-demo"
  force_destroy = true

  tags = { Name = "terraform-018-app" }
}

output "app_bucket_name" {
  value = aws_s3_bucket.app.bucket
}
EOF_TF
```

### Step 2.4 — Initialize the main project with the S3 backend

Replace `YOUR_BUCKET_NAME` with the value from Step 1.4 (or use the `$TFSTATE_BUCKET` variable if your shell still has it):

```bash
cd ~/terraform-018-demo

terraform init \
  -backend-config="bucket=$TFSTATE_BUCKET" \
  -backend-config="key=018-demo/terraform.tfstate" \
  -backend-config="region=ap-south-1"
```

Expected output:

```
Initializing the backend...

Successfully configured the backend "s3"!
Terraform will automatically use this backend unless the backend configuration changes.

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Installing hashicorp/aws v6.x.x...

Terraform has been successfully initialized!
```

**What the `-backend-config` flags do:**

| Flag | Value | Meaning |
|------|-------|---------|
| `bucket` | `terraform-018-tfstate-lazje1gv` | S3 bucket that holds the state file |
| `key` | `018-demo/terraform.tfstate` | Path (prefix + filename) inside the bucket |
| `region` | `ap-south-1` | AWS region where the bucket lives |

### Step 2.5 — Apply the main project

```bash
terraform apply
```

Expected output:

```
Terraform will perform the following actions:

  # aws_s3_bucket.app will be created

Plan: 1 to add, 0 to change, 0 to destroy.

Do you want to perform these actions? yes

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

app_bucket_name = "terraform-018-app-bucket-demo"
```

---

## Step 3 — Verify State Is Stored in S3

```bash
aws s3 ls s3://$TFSTATE_BUCKET/018-demo/
```

Expected output:

```
2025-05-21 10:34:17       2974 terraform.tfstate
```

The `terraform.tfstate` file (2974 bytes) lives in S3, not on your local disk. Any teammate who runs `terraform init` with the same `-backend-config` values will read and write this same file.

You can also inspect the state directly:

```bash
aws s3 cp s3://$TFSTATE_BUCKET/018-demo/terraform.tfstate - | python3 -m json.tool | head -30
```

---

## Step 4 — Destroy in the Correct Order

**Order matters:** the main project's state lives inside the bootstrap bucket. Destroy the bootstrap bucket first and you lose the state file — Terraform can no longer manage the app bucket cleanly.

Always destroy main first, then bootstrap.

### Step 4.1 — Destroy the main project

```bash
cd ~/terraform-018-demo
terraform destroy
```

Type `yes` when prompted. This deletes `terraform-018-app-bucket-demo` and removes the state file from S3.

### Step 4.2 — Destroy the bootstrap project

```bash
cd ~/terraform-018-demo/bootstrap
terraform destroy
```

Type `yes` when prompted. This deletes the `terraform-018-tfstate-lazje1gv` bucket along with any remaining objects in it (thanks to `force_destroy = true`).

### Step 4.3 — Clean up local Terraform cache

```bash
cd ~/terraform-018-demo/bootstrap
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup

cd ~/terraform-018-demo
rm -rf .terraform .terraform.lock.hcl
```

---

## Common Errors

### "No valid credential sources found"

```
Error: configuring Terraform AWS Provider: no valid credential sources for
Terraform AWS Provider found.
```

**Cause:** AWS CLI is not configured, or credentials have expired.

**Fix:**
```bash
aws configure
# or, if using a role:
aws sts get-caller-identity
```

### "BucketAlreadyExists" on apply

S3 bucket names are globally unique across all AWS accounts. If `terraform-018-app-bucket-demo` is already taken by another account, change the bucket name in `main.tf`.

### Backend config mismatch on re-init

If you run `terraform init` a second time with different `-backend-config` values, Terraform will ask:

```
Do you want to copy existing state to the new backend? yes/no
```

Answer `yes` to migrate state, or `no` to start fresh.

---

## Concept Summary

| Concept | What It Does |
|---------|--------------|
| `backend "s3" {}` | Declares S3 as the remote state store; left empty so values are injected at init |
| `-backend-config="key=value"` | Passes backend configuration at `terraform init` without hardcoding in `.tf` files |
| `key = "018-demo/terraform.tfstate"` | Path inside the bucket; use a unique prefix per environment/project |
| `force_destroy = true` | Allows `terraform destroy` to delete an S3 bucket that still contains objects |
| `versioning_configuration { status = "Enabled" }` | Keeps every previous version of the state file; enables rollback |
| Remote state benefits | Shared truth, no local file conflicts, audit trail via S3 versioning |
| Bootstrap pattern | Small separate project creates the bucket with local state; avoids circular dependency |

---

## Tags Used in This Lab

Tags in this lab follow the pattern used at `robochef.co` and `chillbotindia.com` — short, environment-aware name tags that make it easy to filter resources in the AWS console:

```hcl
tags = {
  Name    = "terraform-018-state-bucket"
  Owner   = "saravanans"
  Project = "terraform-4days"
  Env     = "demo"
}
```

---

## Key Takeaways

1. **Never use local state for shared infrastructure.** The moment a second engineer runs `terraform apply`, you have two diverging state files.
2. **The bootstrap pattern solves the chicken-and-egg problem.** The state bucket is created by a small local-state project; everything else uses that bucket as a backend.
3. **Empty `backend "s3" {}`** is not a mistake — it is the recommended way to keep environment-specific values out of version control.
4. **Destroy order is critical:** main project first, bootstrap project second.
5. **Versioning on the state bucket** is cheap insurance. Keep it enabled.
