# 047 — Terraform Provider Aliasing: Multi-Region Deployment

**By:** Saravanan Sundaramoorthy
**Environment:** AWS (ap-south-1 + ap-southeast-1)
**Time:** ~15 minutes

## Topic

Terraform providers are normally configured once and applied globally. But real-world infrastructure often spans multiple regions — or multiple accounts. The `alias` meta-argument on a provider block lets you define **multiple configurations of the same provider** within a single Terraform root module, each with its own settings.

Resources and data sources then select which provider configuration to use via the `provider` meta-argument (`provider = aws.mumbai`). This is called **provider aliasing**.

**Why provider aliasing matters:**

| Scenario | How aliasing helps |
|---|---|
| Multi-region deployment | Deploy resources in ap-south-1 and ap-southeast-1 simultaneously |
| Multi-account management | Use separate AWS profiles or IAM role assumptions per account |
| DR (disaster recovery) | Mirror resources across regions from a single config |
| Cross-region data reads | Read AMI IDs or VPC info from a different region |
| Module composition | Pass a specific provider alias into a child module |

**The default provider rule:** When you have a provider block without an alias, it becomes the default for that provider. Resources that do not specify `provider = ...` use the default automatically. If _all_ your provider blocks have aliases, you must set the provider on every resource that uses that provider — Terraform will error otherwise.

---

## What Terraform Creates

```text
random_string.suffix              → 6-character lowercase suffix (shared across both regions)
aws_s3_bucket.mumbai              → robochef-mumbai-<suffix> in ap-south-1
aws_s3_bucket.singapore           → robochef-singapore-<suffix> in ap-southeast-1
data.aws_region.mumbai            → Confirms the resolved region name for Mumbai provider
data.aws_region.singapore         → Confirms the resolved region name for Singapore provider
```

---

## File Layout

```text
047-provider-aliasing/
├── providers.tf
├── main.tf
└── outputs.tf
```

---

## Step 1 — Create the Working Directory

```bash
mkdir -p ~/terraform-labs/047-provider-aliasing
cd ~/terraform-labs/047-provider-aliasing
```

---

## Step 2 — providers.tf

```hcl
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

# Default provider — Mumbai (ap-south-1)
# Note: alias = "mumbai" means this is NOT the implicit default.
# Every resource must explicitly declare provider = aws.mumbai or aws.singapore.
provider "aws" {
  region = "ap-south-1"
  alias  = "mumbai"
}

# Second provider configuration — Singapore (ap-southeast-1)
provider "aws" {
  region = "ap-southeast-1"
  alias  = "singapore"
}
```

**Key point:** Because both `aws` provider blocks carry an `alias`, neither is the automatic default. If you add a resource without `provider = aws.<alias>`, Terraform will complain that there is no default `aws` provider. This is intentional — it forces you to be explicit about which region each resource lives in.

---

## Step 3 — main.tf

```hcl
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
```

---

## Step 4 — outputs.tf

```hcl
output "mumbai_bucket_name" {
  description = "Name of the S3 bucket created in ap-south-1 (Mumbai)"
  value       = aws_s3_bucket.mumbai.bucket
}

output "singapore_bucket_name" {
  description = "Name of the S3 bucket created in ap-southeast-1 (Singapore)"
  value       = aws_s3_bucket.singapore.bucket
}

output "mumbai_region" {
  description = "Resolved region name from the Mumbai provider"
  value       = data.aws_region.mumbai.name
}

output "singapore_region" {
  description = "Resolved region name from the Singapore provider"
  value       = data.aws_region.singapore.name
}
```

---

## Step 5 — Init and Plan

```bash
terraform init
terraform plan
```

Expected plan summary:

```
Plan: 3 to add, 0 to change, 0 to destroy.
  + random_string.suffix
  + aws_s3_bucket.mumbai
  + aws_s3_bucket.singapore
```

Notice that the two `data` sources are read during plan (not counted in "to add").

---

## Step 6 — Apply

```bash
terraform apply
```

Terraform contacts both AWS regional endpoints in parallel. You will see both bucket creation calls go out simultaneously.

Sample output after apply:

```
Outputs:

mumbai_bucket_name    = "robochef-mumbai-a3f9xq"
singapore_bucket_name = "robochef-singapore-a3f9xq"
mumbai_region         = "ap-south-1"
singapore_region      = "ap-southeast-1"
```

---

## Step 7 — Verify Both Regions

```bash
# List buckets in Mumbai
aws s3 ls --region ap-south-1 | grep robochef-mumbai

# List buckets in Singapore
aws s3 ls --region ap-southeast-1 | grep robochef-singapore
```

Both buckets exist simultaneously under a single `terraform apply`. No manual console switching needed.

---

## Key Concepts Deep Dive

### 1. No-alias = default provider

```hcl
# This block has NO alias — it becomes the default aws provider.
# Any resource without an explicit provider = ... uses this automatically.
provider "aws" {
  region = "ap-south-1"
}
```

If you mix aliased and non-aliased blocks, the non-aliased one wins as the implicit default for resources that omit `provider = ...`.

---

### 2. Multi-account with assume_role

You can target separate AWS accounts by adding `assume_role` to each provider block:

```hcl
provider "aws" {
  alias  = "prod"
  region = "ap-south-1"
  assume_role {
    role_arn = "arn:aws:iam::111122223333:role/TerraformDeployRole"
  }
}

provider "aws" {
  alias  = "staging"
  region = "ap-south-1"
  assume_role {
    role_arn = "arn:aws:iam::444455556666:role/TerraformDeployRole"
  }
}
```

Or use named profiles:

```hcl
provider "aws" {
  alias   = "prod"
  region  = "ap-south-1"
  profile = "prod-account"
}
```

---

### 3. Passing a provider alias into a module

Modules do not inherit provider aliases automatically. You pass them explicitly using the `providers` map:

```hcl
module "singapore_infra" {
  source = "./modules/app-infra"

  providers = {
    aws = aws.singapore   # module's "aws" = our aliased singapore block
  }
}
```

Inside the module, resources simply write `provider = aws` (no alias needed — the alias is resolved at the calling level).

---

### 4. Common mistake — forgetting the alias on a resource

```hcl
# WRONG — no provider specified, but there is no default aws provider
resource "aws_s3_bucket" "oops" {
  bucket = "my-bucket"
}

# Error: The module root requires a provider "aws" with no additional
# configuration. Add an alias-free aws provider block to fix this.
```

Fix: either add an alias-free `provider "aws"` block, or add `provider = aws.mumbai` to the resource.

---

## Destroy

```bash
terraform destroy
rm -rf .terraform
```

Terraform sends delete requests to both regions in parallel. Verify:

```bash
aws s3 ls --region ap-south-1  | grep robochef-mumbai     # should be gone
aws s3 ls --region ap-southeast-1 | grep robochef-singapore  # should be gone
```

---

## Summary

| Concept | Detail |
|---|---|
| `alias` meta-arg | Defined on a `provider {}` block; names the configuration |
| `provider` meta-arg | Used on a resource/data block; selects which alias to use |
| Default provider | An alias-free provider block; resources without `provider =` use it |
| Multi-account | Use `assume_role` or `profile` inside the provider block |
| Modules | Pass aliases via `providers = { aws = aws.singapore }` |
| Parallel apply | Terraform contacts aliased regional endpoints concurrently |

Provider aliasing is the foundation for any Terraform design that manages infrastructure across more than one region or account without splitting into separate Terraform root modules.
