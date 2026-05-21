# 026 — Writing a Reusable Terraform Module for S3 Bucket Creation

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~20 minutes

## Topic

This lab creates a **reusable Terraform module** that encapsulates S3 bucket creation as a single, shareable unit. Once written, the module is called from other projects — you pass in a bucket name and a few options, and the module handles everything: the bucket itself, versioning, and public access blocking.

**No resources are deployed in this lab.** The module is written and validated here, then used in lab 027.

**New concepts in this lab:**

- Module file structure — `main.tf`, `variables.tf`, `outputs.tf` inside a named folder
- `bool` variable type with `default`
- Ternary operator — `var.enable_versioning ? "Enabled" : "Suspended"`
- `merge()` — combine a default tag map with caller-supplied tags
- `force_destroy` — controls whether Terraform can delete a non-empty bucket
- `aws_s3_bucket_public_access_block` — enforces private-only access at the bucket level
- Module source path — how a caller references a local module

---

## 1. What This Module Encapsulates

A single S3 bucket in AWS requires at least three separate resources to be considered production-ready:

```text
aws_s3_bucket                   → the bucket itself
aws_s3_bucket_versioning        → keep previous object versions
aws_s3_bucket_public_access_block → block all public access
```

Without a module, every project that needs an S3 bucket must repeat all three resource blocks. With a module, all three are packaged together — the caller only provides the bucket name and a handful of options.

**Module structure:**

```text
~/terraform-modules/
└── s3-bucket/
    ├── main.tf        ← resource definitions
    ├── variables.tf   ← input variables
    └── outputs.tf     ← exposed values
```

The module lives at `~/terraform-modules/s3-bucket/`. Any Terraform project on the same machine can reference it with a relative path.

---

## 2. Difference from Lab 017 — Standalone vs. Reusable

In lab 017, the S3 bucket was created as a **standalone configuration** — all code lived in a single project folder and was not intended to be shared.

| | Lab 017 | Lab 026 (this lab) |
|---|---|---|
| Location | `~/terraform-aws-s3-017-demo/` | `~/terraform-modules/s3-bucket/` |
| Purpose | One-off demo with PUT/GET objects | Reusable building block for any project |
| Versioning | Hardcoded `"Enabled"` | Controlled by a `bool` variable |
| Public access block | Not included | Always enforced |
| Tags | Hardcoded in `main.tf` | Merged from caller + module default |
| `force_destroy` | Not set | Exposed as a variable (defaults to `false`) |
| Called with `module {}` | No | Yes — lab 027 calls this module |

A standalone configuration is fine for a one-time demo. A module is the right choice when the same infrastructure pattern is needed across multiple projects or environments.

---

## 3. Create the Module Directory

```bash
mkdir -p ~/terraform-modules/s3-bucket
cd ~/terraform-modules/s3-bucket
```

The folder name (`s3-bucket`) is the module name. It does not need to match the bucket name — it describes the type of infrastructure the module creates.

---

## 4. Module File: `variables.tf`

```bash
cat > ~/terraform-modules/s3-bucket/variables.tf <<'EOF_TF'
variable "bucket_name" {
  description = "S3 bucket name (must be globally unique)"
  type        = string
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Delete all objects on bucket destroy"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to the bucket"
  type        = map(string)
  default     = {}
}
EOF_TF
```

**Variable breakdown:**

| Variable | Type | Default | Required? |
|---|---|---|---|
| `bucket_name` | `string` | none | Yes — caller must provide |
| `enable_versioning` | `bool` | `true` | No |
| `force_destroy` | `bool` | `false` | No |
| `tags` | `map(string)` | `{}` | No |

`bucket_name` has no default — this forces every caller to explicitly supply a name, preventing accidental reuse of the same bucket name across environments.

### Why `bool` for `enable_versioning`?

`bool` is a cleaner interface than `string`. The caller writes `enable_versioning = true` instead of `versioning_status = "Enabled"`. The module translates the `bool` to the string the AWS provider expects internally.

---

## 5. Concept: `force_destroy = false` Is the Safe Default

```hcl
variable "force_destroy" {
  description = "Delete all objects on bucket destroy"
  type        = bool
  default     = false
}
```

By default, AWS refuses to delete a non-empty S3 bucket. Terraform inherits this behaviour — a `terraform destroy` on a bucket with objects in it will fail with an error.

Setting `force_destroy = true` tells Terraform to delete every object in the bucket before deleting the bucket itself. This is convenient for test environments where the bucket holds throwaway data.

**The default is `false` for a reason** — it prevents accidental data loss. If someone runs `terraform destroy` against a production bucket that has `force_destroy = true`, all objects are gone permanently, with no recovery from S3 alone.

**Rule of thumb:**

| Environment | Recommended `force_destroy` |
|---|---|
| Production | `false` (default) |
| Staging | `false` |
| Dev / test | `true` |

In lab 027, `force_destroy = true` is set explicitly in the caller because the bucket is a test environment. The module defaults protect production callers who forget to set it.

---

## 6. Module File: `main.tf`

```bash
cat > ~/terraform-modules/s3-bucket/main.tf <<'EOF_TF'
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = merge({ ManagedBy = "terraform" }, var.tags)
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
EOF_TF
```

The resource label `this` is a convention for modules — when a module creates exactly one resource of a type, naming it `this` keeps the code generic. The caller never sees the label; they only see the module's outputs.

### Concept: The Ternary Operator

```hcl
status = var.enable_versioning ? "Enabled" : "Suspended"
```

This is Terraform's ternary (three-part) expression:

```
condition ? value_if_true : value_if_false
```

- If `var.enable_versioning` is `true`, `status` is `"Enabled"`
- If `var.enable_versioning` is `false`, `status` is `"Suspended"`

The AWS provider requires the `versioning_configuration` block to always be present — you cannot omit it to disable versioning. The ternary lets the module accept a simple `bool` from the caller and convert it to the string the provider expects.

### Concept: `merge()` for Default Tags

```hcl
tags = merge({ ManagedBy = "terraform" }, var.tags)
```

`merge()` combines two or more maps into one. Keys from later arguments override keys from earlier ones.

| Expression | Result |
|---|---|
| `merge({ ManagedBy = "terraform" }, {})` | `{ ManagedBy = "terraform" }` |
| `merge({ ManagedBy = "terraform" }, { Owner = "saravanans" })` | `{ ManagedBy = "terraform", Owner = "saravanans" }` |
| `merge({ ManagedBy = "terraform" }, { ManagedBy = "manual" })` | `{ ManagedBy = "manual" }` |

Putting the default map first means a caller can override `ManagedBy` if they need to. The empty `default = {}` on `var.tags` means a caller who supplies no tags still gets the `ManagedBy = "terraform"` tag automatically.

### Concept: `aws_s3_bucket_public_access_block`

S3 buckets can be inadvertently made public through bucket policies or ACLs. The `aws_s3_bucket_public_access_block` resource enforces four independent guardrails at the bucket level, regardless of other settings:

| Attribute | What It Blocks |
|---|---|
| `block_public_acls` | Prevents new ACLs that grant public access |
| `block_public_policy` | Prevents new bucket policies that grant public access |
| `ignore_public_acls` | Ignores any existing public ACLs |
| `restrict_public_buckets` | Blocks all public access through policies |

All four are set to `true` in this module — the module takes an opinionated stance that S3 buckets should never be publicly readable unless the caller explicitly overrides this. This is not exposed as a variable because allowing public access should be a deliberate, exceptional decision made in a separate resource block by the caller, not a module default.

---

## 7. Module File: `outputs.tf`

```bash
cat > ~/terraform-modules/s3-bucket/outputs.tf <<'EOF_TF'
output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.this.arn
}

output "bucket_id" {
  description = "S3 bucket ID"
  value       = aws_s3_bucket.this.id
}

output "versioning_status" {
  description = "Versioning status"
  value       = var.enable_versioning ? "Enabled" : "Suspended"
}
EOF_TF
```

Outputs are the module's public interface — the values a caller can read back after the module runs. The caller references them as `module.app_bucket.bucket_name`, `module.app_bucket.bucket_arn`, and so on.

| Output | Description | Example value |
|---|---|---|
| `bucket_name` | The actual bucket name (same as input) | `robochef-app-bucket-xyz` |
| `bucket_arn` | Full ARN for use in IAM policies | `arn:aws:s3:::robochef-app-bucket-xyz` |
| `bucket_id` | Bucket ID (same as name for S3) | `robochef-app-bucket-xyz` |
| `versioning_status` | Confirms what versioning setting was applied | `Enabled` |

---

## 8. Verify the Module Structure

After creating the three files, confirm the structure:

```bash
ls -1 ~/terraform-modules/s3-bucket/
```

Expected:

```text
main.tf
outputs.tf
variables.tf
```

---

## 9. How to Call This Module (Preview)

A caller — any Terraform project anywhere on the machine — references the module using a `module` block:

```hcl
module "app_bucket" {
  source            = "../../terraform-modules/s3-bucket"
  bucket_name       = "robochef-app-bucket-xyz"
  enable_versioning = true
  force_destroy     = true
  tags = {
    Owner = "saravanans"
    Site  = "robochef.co"
  }
}
```

**How the path works:**

```text
source = "../../terraform-modules/s3-bucket"
```

This is a relative path from the caller's project directory to the module directory. If the caller lives at `~/terraform-aws-026-caller/`, then `../../terraform-modules/s3-bucket` resolves to `~/terraform-modules/s3-bucket/`.

After running `terraform init` in the caller project, Terraform reads the module source and copies it into `.terraform/modules/app_bucket/`.

**What the caller gets back:**

```hcl
output "app_bucket_name" {
  value = module.app_bucket.bucket_name
}

output "app_bucket_arn" {
  value = module.app_bucket.bucket_arn
}
```

**A second caller using a different bucket and different owner:**

```hcl
module "chillbot_bucket" {
  source            = "../../terraform-modules/s3-bucket"
  bucket_name       = "chillbot-media-uploads-prod"
  enable_versioning = true
  force_destroy     = false
  tags = {
    Owner = "saravanans"
    Site  = "chillbotindia.com"
  }
}
```

The same module code serves both callers — one for `robochef.co`, one for `chillbotindia.com`. Neither caller needs to know how versioning or public access blocking works internally.

---

## 10. Module Input/Output Reference Table

### Inputs

| Variable | Type | Default | Description |
|---|---|---|---|
| `bucket_name` | `string` | (required) | S3 bucket name — must be globally unique |
| `enable_versioning` | `bool` | `true` | Enable versioning on the bucket |
| `force_destroy` | `bool` | `false` | Allow destroy even if bucket has objects |
| `tags` | `map(string)` | `{}` | Additional tags to merge onto the bucket |

### Outputs

| Output | Description |
|---|---|
| `bucket_name` | The S3 bucket name as created |
| `bucket_arn` | Full ARN — use in IAM role policies |
| `bucket_id` | Bucket ID — use as `bucket` argument in other resources |
| `versioning_status` | `"Enabled"` or `"Suspended"` based on input |

---

## 11. Full Copy-Paste Setup Script

Use this to create the entire module in one step:

```bash
mkdir -p ~/terraform-modules/s3-bucket

cat > ~/terraform-modules/s3-bucket/variables.tf <<'EOF_TF'
variable "bucket_name" {
  description = "S3 bucket name (must be globally unique)"
  type        = string
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Delete all objects on bucket destroy"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to the bucket"
  type        = map(string)
  default     = {}
}
EOF_TF

cat > ~/terraform-modules/s3-bucket/main.tf <<'EOF_TF'
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = merge({ ManagedBy = "terraform" }, var.tags)
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
EOF_TF

cat > ~/terraform-modules/s3-bucket/outputs.tf <<'EOF_TF'
output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.this.arn
}

output "bucket_id" {
  description = "S3 bucket ID"
  value       = aws_s3_bucket.this.id
}

output "versioning_status" {
  description = "Versioning status"
  value       = var.enable_versioning ? "Enabled" : "Suspended"
}
EOF_TF

echo "Module files created:"
ls -1 ~/terraform-modules/s3-bucket/
```

Expected output:

```text
Module files created:
main.tf
outputs.tf
variables.tf
```

---

## 12. What Happens When Lab 027 Calls This Module

Lab 027 creates a Terraform project that calls this module. When the caller runs `terraform init`:

```text
Initializing modules...
- app_bucket in ../../terraform-modules/s3-bucket

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Installing hashicorp/aws v6.x.x...
```

Terraform reads the module's `required_providers` block (in the module's `main.tf`) and automatically downloads the AWS provider. The caller does not need to declare the provider separately — though declaring it explicitly with a region is recommended for clarity.

When `terraform apply` runs, Terraform creates three resources per module call:

```text
module.app_bucket.aws_s3_bucket.this
module.app_bucket.aws_s3_bucket_versioning.this
module.app_bucket.aws_s3_bucket_public_access_block.this
```

The resource addresses are prefixed with `module.<name>` — this is how Terraform namespaces resources created inside modules, preventing name collisions when multiple modules are called in the same project.

> **Note:** Do not destroy the module files until lab 027 is complete. Lab 027 depends on `~/terraform-modules/s3-bucket/` being present on disk. After lab 027 is finished and resources are destroyed, the module folder can be removed with `rm -rf ~/terraform-modules/s3-bucket/`.

---

## 13. Concept Summary

| Concept | What It Does |
|---|---|
| Module input variables | Define the interface callers use to configure the module — name, type, default, description |
| `bool` variable type | Accepts `true` or `false`; cleaner than asking callers to pass `"Enabled"` / `"Suspended"` strings |
| Ternary operator `? :` | Converts a `bool` to the string the provider requires: `var.enable_versioning ? "Enabled" : "Suspended"` |
| `force_destroy` | Controls whether Terraform deletes bucket objects before deleting the bucket; defaults to `false` to prevent accidental data loss |
| `aws_s3_bucket_public_access_block` | Four-attribute resource that enforces private-only access at the bucket level, independent of ACLs and policies |
| `merge()` | Combines two or more maps — puts the module's default tags alongside caller-supplied tags so `ManagedBy = "terraform"` is always present |
| Module `source` path | Relative or absolute path the caller uses to locate the module folder; Terraform copies it into `.terraform/modules/` on `init` |
| Resource label `this` | Convention for the single primary resource in a module — keeps the code generic and avoids the module leaking internal naming decisions |
| Module outputs | Values the module exposes to callers — referenced as `module.<name>.<output_name>` in the caller's code |
