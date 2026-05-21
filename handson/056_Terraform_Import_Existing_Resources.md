# Lab 056 — Terraform Import: Bringing Existing Resources Under Management
**By: Saravanan Sundaramoorthy**
**Environment:** AWS ap-south-1 (Mumbai)
**Time to complete:** ~25 minutes

---

## Topic

`terraform import` solves the most common day-two Terraform problem: **a resource already exists in AWS but has no Terraform state entry**. This happens when infra is built manually, created by another team, or was originally managed by CloudFormation or CDK and is now being migrated to Terraform.

| Concept | What it means |
|---------|--------------|
| **`terraform import`** | Reads a live AWS resource and writes it into `terraform.tfstate` — nothing is created or destroyed |
| **Unmanaged infrastructure** | Resources that exist in AWS but have no corresponding Terraform state entry |
| **Matching config** | You must write the `resource` block yourself — `terraform import` does NOT generate .tf files |
| **The match problem** | After import, `terraform plan` must show 0 changes; any diff means your config doesn't match reality |
| **`terraform.tfstate`** | The state file that maps `resource.name` → real AWS resource ID |
| **`import {}` block** | Terraform 1.5+ declarative import — works with `-generate-config-out` to auto-write configs |
| **`-generate-config-out`** | Terraform 1.5+ flag that writes a `.tf` file from a live resource — eliminates manual config writing |

---

## Why This Matters

### The "resource already exists" error

Imagine your team created a VPC manually in the AWS console six months ago. Today you decide to manage it with Terraform and write a matching config. You run `terraform apply` — and Terraform tries to **create a new VPC**, not adopt the existing one. AWS rejects the creation:

```
Error: creating EC2 VPC: VpcLimitExceeded: The maximum number of VPCs has been reached.
```

Or for a resource with a globally unique name (like an S3 bucket):

```
Error: creating S3 Bucket (terraform-056-import-demo-saravanans):
BucketAlreadyExists: The requested bucket name is not available.
  The bucket namespace is shared by all users of the system.
  Please select a different name and try again.
  status code: 409, request id: ...
```

**Terraform does not know the resource exists** because nothing is in state. The fix is `terraform import`.

---

## Flow Diagram

```
Scenario A: Import a VPC
─────────────────────────────────────────────────────────

Step 1: Create VPC manually (AWS CLI)
          │
          ▼
        VPC exists in AWS → vpc-0abc12345def67890
        No Terraform state entry
          │
Step 2: Write matching main.tf with aws_vpc "imported"
          │
          ▼
        Resource block exists in config
        State file is EMPTY (or has no entry for this VPC)
          │
Step 3: terraform init
          │
Step 4: (Optional) terraform apply → ERROR: resource already exists
          │
Step 5: terraform import aws_vpc.imported vpc-0abc12345def67890
          │
          ▼
        Terraform reads the live VPC from the AWS API
        Writes all attributes into terraform.tfstate
        "Import successful!"
          │
Step 6: terraform plan → 0 changes (if config matches)
          │
Step 7: terraform destroy (removes VPC from AWS and state)
```

---

## Prerequisites

- AWS CLI configured with credentials for ap-south-1
- Terraform >= 1.5 installed (`terraform version`)
- Permissions: `ec2:CreateVpc`, `ec2:DescribeVpcs`, `s3:CreateBucket`, `s3:DeleteBucket`

---

## Scenario A — Import an Existing VPC

### A.1 — Create project folder

```bash
mkdir -p ~/terraform-import-056
cd ~/terraform-import-056
```

### A.2 — Create a VPC manually (simulates unmanaged infra)

```bash
VPC_ID=$(aws ec2 create-vpc \
  --region ap-south-1 \
  --cidr-block 10.99.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=my-imported-vpc},{Key=Owner,Value=saravanans},{Key=Project,Value=robochef.co}]' \
  --query 'Vpc.VpcId' \
  --output text)

echo "VPC ID: $VPC_ID"
```

Expected output:

```
VPC ID: vpc-0abc12345def67890
```

Verify the VPC exists in AWS:

```bash
aws ec2 describe-vpcs \
  --vpc-ids $VPC_ID \
  --query "Vpcs[0].{ID:VpcId,CIDR:CidrBlock,State:State,Name:Tags[?Key=='Name']|[0].Value}" \
  --output table
```

Expected:

```
-------------------------------------------------------------
|                       DescribeVpcs                        |
+----------------------+----------------+--------+----------+
|         CIDR         |       ID       |  Name  |  State   |
+----------------------+----------------+--------+----------+
|  10.99.0.0/16        |  vpc-0abc...   | my-imported-vpc | available |
+----------------------+----------------+--------+----------+
```

At this point: **the VPC exists in AWS but Terraform has no state entry for it.**

---

### A.3 — Write Terraform configuration

#### `providers.tf`

```bash
cat > providers.tf <<'EOF_TF'
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}
EOF_TF
```

#### `main.tf` — matches the manually-created VPC

```bash
cat > main.tf <<'EOF_TF'
resource "aws_vpc" "imported" {
  cidr_block           = "10.99.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = false

  tags = {
    Name    = "my-imported-vpc"
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}
EOF_TF
```

#### `outputs.tf`

```bash
cat > outputs.tf <<'EOF_TF'
output "vpc_id" {
  description = "Imported VPC ID"
  value       = aws_vpc.imported.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.imported.cidr_block
}

output "vpc_default" {
  description = "Is this the default VPC?"
  value       = aws_vpc.imported.default
}
EOF_TF
```

---

### A.4 — Init

```bash
terraform init
```

Expected output (key lines):

```
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Installing hashicorp/aws v6.x.x...

Terraform has been successfully initialized!
```

---

### A.5 — See the error (what happens WITHOUT import)

Before importing, run `terraform apply` to see what Terraform would do:

```bash
terraform plan
```

Expected output:

```
Terraform used the selected providers to generate the following execution plan.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # aws_vpc.imported will be created
  + resource "aws_vpc" "imported" {
      + arn                                  = (known after apply)
      + cidr_block                           = "10.99.0.0/16"
      + default_route_table_id               = (known after apply)
      + enable_dns_hostnames                 = false
      + enable_dns_support                   = true
      + id                                   = (known after apply)
      ...
      + tags = {
          + "Name"    = "my-imported-vpc"
          + "Owner"   = "saravanans"
          + "Project" = "robochef.co"
        }
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

If you were to run `terraform apply` here, Terraform would try to **create a second VPC** — not adopt the existing one. For resources with unique naming constraints (like S3 buckets), you would immediately see:

```
Error: creating S3 Bucket: BucketAlreadyExists:
  The requested bucket name is not available.
  status code: 409
```

For a VPC this would silently create a duplicate. **This is exactly why import is needed.**

---

### A.6 — Import the VPC into Terraform state

```bash
terraform import aws_vpc.imported $VPC_ID
```

Or if you no longer have the shell variable:

```bash
terraform import aws_vpc.imported vpc-0abc12345def67890
```

Expected output:

```
aws_vpc.imported: Importing from ID "vpc-0abc12345def67890"...
aws_vpc.imported: Import prepared!
  Prepared aws_vpc for import
aws_vpc.imported: Refreshing state... [id=vpc-0abc12345def67890]

Import successful!

The resources that were imported are shown above. These resources are now in
your Terraform state and will henceforth be managed by Terraform.
```

What just happened:
- Terraform called the AWS EC2 API and read every attribute of `vpc-0abc12345def67890`
- It wrote those attributes into `terraform.tfstate`
- **Nothing was created, modified, or destroyed in AWS**

Verify the import succeeded:

```bash
terraform state list
```

Expected:

```
aws_vpc.imported
```

Inspect the full state entry:

```bash
terraform state show aws_vpc.imported
```

Expected output (excerpt):

```
# aws_vpc.imported:
resource "aws_vpc" "imported" {
    arn                                  = "arn:aws:ec2:ap-south-1:123456789012:vpc/vpc-0abc12345def67890"
    assign_generated_ipv6_cidr_block     = false
    cidr_block                           = "10.99.0.0/16"
    default_network_acl_id               = "acl-..."
    default_route_table_id               = "rtb-..."
    default_security_group_id            = "sg-..."
    dhcp_options_id                      = "dopt-..."
    enable_dns_hostnames                 = false
    enable_dns_support                   = true
    id                                   = "vpc-0abc12345def67890"
    instance_tenancy                     = "default"
    main_route_table_id                  = "rtb-..."
    owner_id                             = "123456789012"
    tags                                 = {
        "Name"    = "my-imported-vpc"
        "Owner"   = "saravanans"
        "Project" = "robochef.co"
    }
    tags_all                             = {
        "Name"    = "my-imported-vpc"
        "Owner"   = "saravanans"
        "Project" = "robochef.co"
    }
}
```

---

### A.7 — Run terraform plan (expect 0 changes)

```bash
terraform plan
```

Expected output:

```
aws_vpc.imported: Refreshing state... [id=vpc-0abc12345def67890]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
```

**This is the success condition.** Zero changes means your config perfectly describes the real resource. Terraform now fully manages this VPC — you can `plan`, `apply`, and `destroy` it like any other Terraform-managed resource.

---

### A.8 — Destroy

```bash
terraform destroy -auto-approve
```

Expected:

```
aws_vpc.imported: Destroying... [id=vpc-0abc12345def67890]
aws_vpc.imported: Destruction complete after 1s

Destroy complete! Resources: 1 destroyed.
```

```bash
rm -rf .terraform
```

---

## Scenario B — Import an S3 Bucket (Simpler Example)

S3 buckets are the simplest resource to import because the import ID is just the bucket name. This makes S3 ideal for demonstrating the full import workflow.

### B.1 — Create a bucket manually (unmanaged)

```bash
cd ~/terraform-import-056

aws s3 mb s3://terraform-056-import-demo-saravanans \
  --region ap-south-1

aws s3api put-bucket-tagging \
  --bucket terraform-056-import-demo-saravanans \
  --tagging 'TagSet=[{Key=Owner,Value=saravanans},{Key=Project,Value=chillbotindia.com}]'
```

Expected:

```
make_bucket: terraform-056-import-demo-saravanans
```

Verify the bucket exists:

```bash
aws s3 ls | grep terraform-056
```

Expected:

```
2025-05-21 10:00:00 terraform-056-import-demo-saravanans
```

At this point the bucket has **no Terraform state entry**.

---

### B.2 — Write matching Terraform config

Clear or replace the existing files from Scenario A:

```bash
cat > main.tf <<'EOF_TF'
resource "aws_s3_bucket" "imported" {
  bucket = "terraform-056-import-demo-saravanans"

  tags = {
    Owner   = "saravanans"
    Project = "chillbotindia.com"
  }
}
EOF_TF

cat > outputs.tf <<'EOF_TF'
output "bucket_name" {
  description = "Imported S3 bucket name"
  value       = aws_s3_bucket.imported.id
}

output "bucket_arn" {
  description = "Imported S3 bucket ARN"
  value       = aws_s3_bucket.imported.arn
}

output "bucket_region" {
  description = "Bucket region"
  value       = aws_s3_bucket.imported.region
}
EOF_TF
```

`providers.tf` remains the same from Scenario A (or re-run init if starting fresh).

---

### B.3 — Init (if not already done)

```bash
terraform init
```

---

### B.4 — Demonstrate the "already exists" error

```bash
terraform apply -auto-approve
```

Expected error:

```
aws_s3_bucket.imported: Creating...
╷
│ Error: creating S3 Bucket (terraform-056-import-demo-saravanans):
│ BucketAlreadyOwnedByYou: Your previous request to create the named bucket
│ succeeded and you already own it.
│   status code: 409, request id: ..., host id: ...
╵
```

This is the real-world error. Terraform tried to call `s3:CreateBucket` because the bucket is not in state. The fix is `terraform import`.

---

### B.5 — Import the bucket

For S3, the import ID is simply the **bucket name** (not an ARN, not a URL — just the name):

```bash
terraform import aws_s3_bucket.imported terraform-056-import-demo-saravanans
```

Expected:

```
aws_s3_bucket.imported: Importing from ID "terraform-056-import-demo-saravanans"...
aws_s3_bucket.imported: Import prepared!
  Prepared aws_s3_bucket for import
aws_s3_bucket.imported: Refreshing state... [id=terraform-056-import-demo-saravanans]

Import successful!

The resources that were imported are shown above. These resources are now in
your Terraform state and will henceforth be managed by Terraform.
```

Verify import:

```bash
terraform state list
# aws_s3_bucket.imported

terraform state show aws_s3_bucket.imported
```

---

### B.6 — Run plan (expect 0 changes)

```bash
terraform plan
```

Expected:

```
aws_s3_bucket.imported: Refreshing state... [id=terraform-056-import-demo-saravanans]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
```

---

### B.7 — Destroy

```bash
terraform destroy -auto-approve
rm -rf .terraform
```

Expected:

```
aws_s3_bucket.imported: Destroying... [id=terraform-056-import-demo-saravanans]
aws_s3_bucket.imported: Destruction complete after 1s

Destroy complete! Resources: 1 destroyed.
```

---

## Terraform 1.5+ — Declarative Import Block Syntax

Terraform 1.5 introduced a second way to import: the `import {}` block inside your `.tf` files. This is declarative (config-as-code) instead of imperative (CLI command).

### Syntax

```hcl
import {
  to = aws_s3_bucket.imported
  id = "terraform-056-import-demo-saravanans"
}
```

Add this block to your `main.tf` alongside the resource block. When you run `terraform apply`, Terraform performs the import automatically during the apply phase — no separate `terraform import` command needed.

### Full example with import block

```hcl
# main.tf

import {
  to = aws_s3_bucket.imported
  id = "terraform-056-import-demo-saravanans"
}

resource "aws_s3_bucket" "imported" {
  bucket = "terraform-056-import-demo-saravanans"

  tags = {
    Owner   = "saravanans"
    Project = "chillbotindia.com"
  }
}
```

Run:

```bash
terraform plan
```

Output includes:

```
  # aws_s3_bucket.imported will be imported
    resource "aws_s3_bucket" "imported" {
        bucket = "terraform-056-import-demo-saravanans"
        ...
    }

Plan: 0 to add, 0 to change, 0 to destroy. 1 to import.
```

Then:

```bash
terraform apply
```

After the apply, the `import {}` block can be **removed from main.tf** — it is only needed once.

### CLI vs. Block comparison

| Feature | `terraform import` CLI | `import {}` block |
|---------|------------------------|-------------------|
| Terraform version | All versions | 1.5+ only |
| How it runs | Separate command before apply | Runs during `terraform apply` |
| Config file change | Not required | Block added to .tf file |
| Code-review friendly | No (state change not in PR) | Yes (import is in the PR diff) |
| Bulk imports with `for_each` | No — one resource at a time | Yes — `for_each` on import block |
| Works with `-generate-config-out` | No | Yes |

---

## Terraform 1.5+ — Auto-Generate Config with `-generate-config-out`

The biggest pain in `terraform import` is writing a config that **exactly matches** the real resource. Terraform 1.5 added `-generate-config-out` to solve this.

### How it works

1. Add an `import {}` block to your config (resource block not required yet)
2. Run `terraform plan -generate-config-out=generated.tf`
3. Terraform reads the live resource from AWS and writes a complete `resource` block to `generated.tf`
4. Review and clean up `generated.tf`, then merge into `main.tf`

### Step-by-step example (S3 bucket)

First, create the bucket manually:

```bash
aws s3 mb s3://terraform-056-import-demo-saravanans --region ap-south-1
```

Write only the import block (no resource block yet):

```bash
cat > main.tf <<'EOF_TF'
import {
  to = aws_s3_bucket.imported
  id = "terraform-056-import-demo-saravanans"
}
EOF_TF
```

Run plan with generate flag:

```bash
terraform init
terraform plan -generate-config-out=generated.tf
```

Terraform writes `generated.tf` with all attributes populated from the live bucket:

```hcl
# generated.tf (auto-generated — review before using)
resource "aws_s3_bucket" "imported" {
  bucket              = "terraform-056-import-demo-saravanans"
  bucket_prefix       = null
  force_destroy       = null
  object_lock_enabled = false
  tags                = {}
  tags_all            = {}
}
```

Review and clean it up (remove null values, add your tags, etc.):

```bash
# Move the generated config into main.tf (after review)
cat generated.tf >> main.tf
# Remove the temporary generated file
rm generated.tf
```

Now edit `main.tf` to remove null attributes and add the import block was already there. Your final `main.tf`:

```hcl
import {
  to = aws_s3_bucket.imported
  id = "terraform-056-import-demo-saravanans"
}

resource "aws_s3_bucket" "imported" {
  bucket = "terraform-056-import-demo-saravanans"

  tags = {
    Owner   = "saravanans"
    Project = "chillbotindia.com"
  }
}
```

Run apply to complete the import:

```bash
terraform apply -auto-approve
```

Then clean up the import block (it's no longer needed):

```bash
# Remove the import {} block from main.tf
# Run plan to confirm 0 changes
terraform plan
```

---

## The Match Problem — When Plan Shows Changes After Import

After a successful `terraform import`, running `terraform plan` should show 0 changes. If it shows diffs, **your config does not match the real resource**. You must fix `main.tf` before Terraform starts making unintended changes on the next `apply`.

### Common causes and fixes

| Attribute | Root cause | How to fix |
|-----------|-----------|------------|
| `enable_dns_hostnames` | VPC defaults to `false`; config specifies `true` | Check actual value with `terraform state show`; match it in config |
| `tags` | Extra tag in config not on real resource (or vice versa) | Run `aws ec2 describe-tags` and sync config |
| `instance_type` | Config says `t3.micro`; instance was resized to `t3.small` | Update config or resize instance |
| `ami` | Data source returns a newer AMI than the one the instance runs | Hardcode the exact AMI ID from `terraform state show` |
| `bucket_prefix` | Terraform sets this to null but the provider schema requires it | Set `bucket_prefix = null` explicitly or omit the attribute |
| `object_lock_enabled` | Generated config includes it; your resource block omits it | Add `object_lock_enabled = false` to match |

### How to debug a dirty plan

```bash
terraform plan
```

Look for lines with `~` (update in place) or `-/+` (destroy and recreate):

```
  ~ resource "aws_vpc" "imported" {
      ~ enable_dns_hostnames = false -> true
        id                   = "vpc-0abc12345def67890"
        # (other attributes unchanged)
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

This tells you `enable_dns_hostnames` differs. Check the real value:

```bash
terraform state show aws_vpc.imported | grep enable_dns
```

Then fix your `main.tf` to match and re-run `terraform plan` until it shows 0 changes.

---

## Common AWS Resource Import ID Formats

One of the most common points of confusion with `terraform import` is knowing which ID to pass as the second argument. The format varies by resource type.

| Resource type | Import ID format | Example |
|---------------|-----------------|---------|
| `aws_instance` | EC2 instance ID | `i-0abc12345def67890` |
| `aws_s3_bucket` | Bucket name | `terraform-056-import-demo-saravanans` |
| `aws_vpc` | VPC ID | `vpc-0abc12345def67890` |
| `aws_security_group` | Security Group ID | `sg-0abc12345def67890` |
| `aws_iam_role` | Role name | `my-ecs-task-role` |
| `aws_db_instance` | DB instance identifier | `my-rds-postgres` |
| `aws_subnet` | Subnet ID | `subnet-0abc12345def67890` |
| `aws_route_table` | Route table ID | `rtb-0abc12345def67890` |
| `aws_internet_gateway` | Internet Gateway ID | `igw-0abc12345def67890` |
| `aws_iam_policy` | Policy ARN | `arn:aws:iam::123456789012:policy/MyPolicy` |
| `aws_ecs_cluster` | Cluster name | `my-ecs-cluster` |
| `aws_lambda_function` | Function name | `my-lambda-function` |
| `aws_elasticache_cluster` | Cluster ID | `my-redis-cluster` |
| `aws_cloudwatch_log_group` | Log group name | `/aws/lambda/my-function` |
| `aws_sns_topic` | Topic ARN | `arn:aws:sns:ap-south-1:123456789012:my-topic` |

> **Tip:** When in doubt, check the Terraform AWS provider documentation for the specific resource. Each resource's docs page has an "Import" section at the bottom that shows the exact format.

Find the import format quickly:

```bash
# Search on the CLI
terraform providers schema -json | jq '.provider_schemas."registry.terraform.io/hashicorp/aws".resource_schemas | keys[]' | grep aws_s3
```

Or look at the Terraform Registry: `https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/<resource_name>#import`

---

## Key Teaching Points

### 1. `terraform import` only updates state — it does NOT write .tf config

```
What import DOES:                   What import does NOT do:
─────────────────────────────────   ─────────────────────────────────────
Reads resource from AWS API         Write main.tf or any .tf file for you
Writes to terraform.tfstate         Validate that your config is correct
Maps resource block → real AWS ID   Generate outputs.tf
Reports "Import successful!"        Run terraform apply
                                    Create or destroy anything in AWS
```

You must write (or have already written) the matching `resource` block before running `terraform import`. Without it:

```
Error: resource address "aws_vpc.imported" does not exist in the configuration.

Before importing this resource, please create its configuration in the root module.
For more information, please see the documentation on the import command.
```

### 2. Config must match reality — run plan after import to detect drift

Immediately after every import, run:

```bash
terraform plan
```

If the plan shows 0 changes, you are done. If it shows changes, fix `main.tf` to match the real resource. Do NOT run `terraform apply` until the plan is clean — otherwise Terraform will mutate (or destroy and recreate) the resource to match your (incorrect) config.

### 3. Import block syntax (1.5+) is declarative and works with `-generate-config-out`

The `import {}` block lives in your `.tf` files and is committed to version control. This means imports are visible in code reviews, auditable, and repeatable. Combine with `-generate-config-out` to auto-generate configs from live resources.

### 4. One resource at a time with CLI import — use `for_each` import blocks for bulk

```bash
# CLI import: one resource per command
terraform import aws_s3_bucket.bucket1 bucket-one
terraform import aws_s3_bucket.bucket2 bucket-two
terraform import aws_s3_bucket.bucket3 bucket-three
```

With `import {}` blocks and `for_each` (Terraform 1.5+):

```hcl
locals {
  buckets = {
    bucket1 = "bucket-one"
    bucket2 = "bucket-two"
    bucket3 = "bucket-three"
  }
}

import {
  for_each = local.buckets
  to       = aws_s3_bucket.buckets[each.key]
  id       = each.value
}

resource "aws_s3_bucket" "buckets" {
  for_each = local.buckets
  bucket   = each.value
}
```

A single `terraform apply` imports all three buckets simultaneously.

### 5. Common problem: plan after import shows changes

This means your config doesn't match the real attributes. Read the diff output carefully — each `~` tells you exactly which attribute differs. Use `terraform state show <resource>` to see all real values.

### 6. The `moved` block is different — it moves resources within state, not from outside

```hcl
# moved block: renames/moves a resource within Terraform state
moved {
  from = aws_s3_bucket.old_name
  to   = aws_s3_bucket.new_name
}
```

Use `moved` when you refactor your config (rename a resource block, move it into a module). Use `terraform import` when a resource exists in AWS but has no Terraform state entry at all.

| Tool | Use case |
|------|----------|
| `terraform import` | Resource exists in AWS, not in state |
| `moved {}` block | Resource in state, but resource address changed in config |
| `terraform state mv` | Same as moved, but via CLI instead of config |
| `terraform state rm` | Remove a resource from state (without destroying it in AWS) |

---

## Concept Summary

| Concept | Key rule |
|---------|----------|
| `terraform import` | Reads from AWS, writes to state — never creates or destroys |
| Config required first | Write the `resource` block before running import |
| `terraform plan` after import | Must show 0 changes — any diff means fix your config |
| Match problem | Align every attribute with what `terraform state show` reports |
| `terraform state list` | Lists all resources currently tracked in state |
| `terraform state show` | Prints every attribute of a specific resource in state |
| Import ID format | Varies by resource — check the provider docs "Import" section |
| `import {}` block | Terraform 1.5+ declarative import — visible in code review |
| `-generate-config-out` | Auto-writes .tf config from a live resource (requires import block) |
| `for_each` on import block | Bulk imports in a single apply |
| `moved {}` block | Renames/moves within state — NOT for importing from outside Terraform |
| After import, full lifecycle | Resource is now managed: plan, apply, destroy all work normally |

---

## Full Copy-Paste Script — Scenario A (VPC)

```bash
#!/usr/bin/env bash
set -euo pipefail

mkdir -p ~/terraform-import-056
cd ~/terraform-import-056

# ── Step 1: Create VPC manually ───────────────────────────────────────────────
VPC_ID=$(aws ec2 create-vpc \
  --region ap-south-1 \
  --cidr-block 10.99.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=my-imported-vpc},{Key=Owner,Value=saravanans},{Key=Project,Value=robochef.co}]' \
  --query 'Vpc.VpcId' \
  --output text)

echo "VPC ID: $VPC_ID"

aws ec2 describe-vpcs \
  --vpc-ids "$VPC_ID" \
  --query "Vpcs[0].{ID:VpcId,CIDR:CidrBlock,State:State}" \
  --output table

# ── Step 2: Write Terraform files ─────────────────────────────────────────────
cat > providers.tf <<'EOF_TF'
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}
EOF_TF

cat > main.tf <<'EOF_TF'
resource "aws_vpc" "imported" {
  cidr_block           = "10.99.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = false

  tags = {
    Name    = "my-imported-vpc"
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}
EOF_TF

cat > outputs.tf <<'EOF_TF'
output "vpc_id" {
  description = "Imported VPC ID"
  value       = aws_vpc.imported.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.imported.cidr_block
}
EOF_TF

# ── Step 3: Init ──────────────────────────────────────────────────────────────
terraform init

# ── Step 4: Import ────────────────────────────────────────────────────────────
terraform import aws_vpc.imported "$VPC_ID"

# ── Step 5: Verify state ──────────────────────────────────────────────────────
terraform state list
terraform state show aws_vpc.imported

# ── Step 6: Plan should show 0 changes ────────────────────────────────────────
terraform plan

# ── Step 7: Destroy ───────────────────────────────────────────────────────────
terraform destroy -auto-approve
rm -rf .terraform
```

---

## Full Copy-Paste Script — Scenario B (S3 Bucket)

```bash
#!/usr/bin/env bash
set -euo pipefail

mkdir -p ~/terraform-import-056
cd ~/terraform-import-056

BUCKET_NAME="terraform-056-import-demo-saravanans"

# ── Step 1: Create bucket manually ────────────────────────────────────────────
aws s3 mb "s3://$BUCKET_NAME" --region ap-south-1

aws s3api put-bucket-tagging \
  --bucket "$BUCKET_NAME" \
  --tagging 'TagSet=[{Key=Owner,Value=saravanans},{Key=Project,Value=chillbotindia.com}]'

echo "Bucket created: $BUCKET_NAME"
aws s3 ls | grep "$BUCKET_NAME"

# ── Step 2: Write Terraform files ─────────────────────────────────────────────
cat > providers.tf <<'EOF_TF'
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}
EOF_TF

cat > main.tf <<EOF_TF
resource "aws_s3_bucket" "imported" {
  bucket = "$BUCKET_NAME"

  tags = {
    Owner   = "saravanans"
    Project = "chillbotindia.com"
  }
}
EOF_TF

cat > outputs.tf <<'EOF_TF'
output "bucket_name" {
  description = "Imported S3 bucket name"
  value       = aws_s3_bucket.imported.id
}

output "bucket_arn" {
  description = "Imported S3 bucket ARN"
  value       = aws_s3_bucket.imported.arn
}
EOF_TF

# ── Step 3: Init ──────────────────────────────────────────────────────────────
terraform init

# ── Step 4 (optional): See the error without import ───────────────────────────
# terraform apply -auto-approve  # ← would fail with BucketAlreadyOwnedByYou

# ── Step 5: Import ────────────────────────────────────────────────────────────
terraform import "aws_s3_bucket.imported" "$BUCKET_NAME"

# ── Step 6: Verify state ──────────────────────────────────────────────────────
terraform state list
terraform state show aws_s3_bucket.imported

# ── Step 7: Plan should show 0 changes ────────────────────────────────────────
terraform plan

# ── Step 8: Destroy ───────────────────────────────────────────────────────────
terraform destroy -auto-approve
rm -rf .terraform
```

---

## Quick Reference — Import Workflow Checklist

```
Before import:
  [ ] Resource exists in AWS (console, CLI, another IaC tool)
  [ ] Resource block written in main.tf
  [ ] terraform init done
  [ ] Know the import ID format for this resource type

During import:
  terraform import <resource_type>.<name> <id>
  terraform state list   # verify resource appears
  terraform state show   # inspect all attributes

After import:
  terraform plan         # must show 0 changes
  [ ] If plan shows changes → fix main.tf to match state
  [ ] Remove import {} block (if used) after apply
  [ ] Commit terraform.tfstate (or push to remote backend)

Cleanup:
  terraform destroy -auto-approve
  rm -rf .terraform
```
