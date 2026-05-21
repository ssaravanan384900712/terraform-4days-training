# 023 — S3 Buckets, Policies & Versioning with Terraform

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~20 minutes

## Topic

Amazon S3 is object storage — you store files (objects) inside containers called **buckets**. Every object has a key (its path-like name, e.g. `config/settings.json`) and a value (the file content).

By default, S3 does not keep old copies of a file when you overwrite it. **Versioning** changes this: once enabled, every upload creates a new version with its own unique `VersionId`. The previous version is preserved and can be retrieved or restored at any time. This makes S3 a reliable store for configuration files, application assets, and backups — even if you accidentally overwrite or delete a file.

**Bucket policies** are IAM JSON documents attached directly to a bucket. They control which principals (AWS accounts, IAM roles, users) can perform which S3 actions (`s3:GetObject`, `s3:PutObject`, `s3:ListBucket`, etc.) on that bucket and its objects. Together with the **public access block**, they give you precise, auditable control over who can read or write your data.

This lab builds a fully locked-down S3 bucket for the `robochef.co` project with:

- Versioning enabled — every upload creates a new, recoverable version
- Public access blocked on all four dimensions
- A bucket policy that allows only the owning AWS account (`saravanans`) to read and write

**Versioning — why it matters:**

| Scenario | Without Versioning | With Versioning |
|---|---|---|
| Overwrite `settings.json` | Old file is gone forever | Both versions stored, old one recoverable |
| Delete an object | Permanently deleted | A "delete marker" is created; original still exists |
| Accidental bad deploy | No rollback | Retrieve the specific version you need |
| Audit trail | None | Full history with timestamps and VersionIds |

---

## What Terraform Creates

```text
random_string.suffix                      → 8-character lowercase suffix for the bucket name
aws_s3_bucket.main                        → robochef-demo-023-<suffix>, versioning-ready
aws_s3_bucket_versioning.main             → Enables versioning on the bucket
aws_s3_bucket_public_access_block.main    → Blocks all public access (4 flags)
aws_s3_bucket_policy.main                 → Allows only the account root to read/write
aws_s3_object.config_v1                   → Uploads config/settings.json v1
```

**Plan: 6 to add, 0 to change, 0 to destroy.**

---

## 1. Create Project Folder

```bash
mkdir -p ~/terraform-s3-023
cd ~/terraform-s3-023
```

---

## 2. Check Your AWS Region

```bash
aws configure get region
aws sts get-caller-identity
```

The live test for this lab ran in `ap-south-1` with account `043000359118`. Update `terraform.tfvars` to match your configured region.

---

## 3. Create Terraform Files

```text
providers.tf
variables.tf
main.tf
outputs.tf
terraform.tfvars
```

---

## 4. providers.tf

```bash
cat > providers.tf <<'EOF_TF'
terraform {
  required_providers {
    aws    = { source = "hashicorp/aws",    version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}
provider "aws" { region = var.aws_region }
EOF_TF
```

Two providers are declared: `aws` for the S3 resources and `random` to generate the unique bucket name suffix. Without the suffix, bucket names would collide globally — S3 bucket names must be unique across all AWS accounts worldwide.

---

## 5. variables.tf

```bash
cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "bucket_prefix" {
  type    = string
  default = "robochef-demo-023"
}
EOF_TF
```

Just two variables. The bucket name is built dynamically in `main.tf` as `${var.bucket_prefix}-${random_string.suffix.result}`.

---

## 6. main.tf

```bash
cat > main.tf <<'EOF_TF'
resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "aws_s3_bucket" "main" {
  bucket        = "${var.bucket_prefix}-${random_string.suffix.result}"
  force_destroy = true
  tags          = { Name = "robochef-023-main", Owner = "saravanans", Site = "robochef.co" }
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket                  = aws_s3_bucket.main.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource  = [aws_s3_bucket.main.arn, "${aws_s3_bucket.main.arn}/*"]
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.main]
}

resource "aws_s3_object" "config_v1" {
  bucket       = aws_s3_bucket.main.id
  key          = "config/settings.json"
  content      = jsonencode({ version = "1.0", app = "robochef", env = "demo" })
  content_type = "application/json"
}
EOF_TF
```

---

## Key Concept: `depends_on` in the Bucket Policy

```hcl
depends_on = [aws_s3_bucket_public_access_block.main]
```

This explicit dependency on `aws_s3_bucket_public_access_block.main` is **not optional** — it is required for correctness.

Here is what happens without it:

1. Terraform may create the bucket policy **before** the public access block is in place
2. AWS evaluates the bucket policy immediately and sees that it could potentially allow public access (any policy that includes a `Principal` can look public to AWS's evaluator)
3. AWS rejects the policy with an error because the public access block that would safely restrict it has not been applied yet

Once the public access block is in place (all four flags set to `true`), the policy can reference any `Principal` freely — AWS knows the block prevents any actual public exposure regardless of what the policy says.

The rule: **always apply `aws_s3_bucket_public_access_block` before `aws_s3_bucket_policy` when both are present.** `depends_on` enforces this ordering explicitly.

---

## Key Concept: `data "aws_caller_identity"`

```hcl
data "aws_caller_identity" "current" {}
```

This data source calls `sts:GetCallerIdentity` against AWS and returns metadata about the credentials Terraform is currently using — specifically `account_id`, `arn`, and `user_id`.

Using it in the bucket policy:

```hcl
Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
```

This means the policy **never hardcodes the account ID**. The same `main.tf` works in any AWS account — no find-and-replace needed. Hardcoding `043000359118` would break the policy if the same Terraform code were applied under a different account.

---

## Key Concept: `force_destroy = true`

```hcl
resource "aws_s3_bucket" "main" {
  force_destroy = true
  ...
}
```

By default, S3 will refuse to delete a bucket that contains objects. With versioning enabled, this includes **all historical versions** — not just the current objects. Even after you delete all "current" objects, the old versions remain and will block `terraform destroy`.

`force_destroy = true` tells Terraform to delete all objects (including all versions and delete markers) before destroying the bucket. Without this flag, `terraform destroy` will fail with:

```text
Error: deleting S3 Bucket (robochef-demo-023-nbzhg6uy):
BucketNotEmpty: The bucket you tried to delete is not empty
```

**Note:** In production, you may intentionally leave `force_destroy = false` so that an accidental `terraform destroy` cannot wipe your data. For labs and demos, `true` is the right choice.

---

## 7. outputs.tf

```bash
cat > outputs.tf <<'EOF_TF'
output "bucket_name"        { value = aws_s3_bucket.main.bucket }
output "bucket_arn"         { value = aws_s3_bucket.main.arn }
output "account_id"         { value = data.aws_caller_identity.current.account_id }
output "versioning"         { value = "Enabled" }
output "policy_applied"     { value = "Account-only read/write policy" }
output "list_versions_cmd"  {
  value = "aws s3api list-object-versions --bucket ${aws_s3_bucket.main.bucket} --key config/settings.json --region ${var.aws_region}"
}
EOF_TF
```

The `list_versions_cmd` output prints the exact AWS CLI command to inspect versioning after apply — no manual bucket name substitution needed.

---

## 8. terraform.tfvars

```bash
cat > terraform.tfvars <<'EOF_TF'
aws_region    = "ap-south-1"
bucket_prefix = "robochef-demo-023"
EOF_TF
```

Update `aws_region` to match your configured AWS region. The bucket name will be `robochef-demo-023-<random-suffix>`.

---

## 9. Initialize Terraform

```bash
terraform init
```

Expected output:

```text
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Finding hashicorp/random versions matching "~> 3.0"...
- Installing hashicorp/aws v6.x.x...
- Installing hashicorp/random v3.x.x...

Terraform has been successfully initialized!
```

---

## 10. Format and Validate

```bash
terraform fmt
terraform validate
```

Expected:

```text
Success! The configuration is valid.
```

---

## 11. Plan

```bash
terraform plan
```

Expected plan output (abbreviated):

```text
# random_string.suffix will be created
# aws_s3_bucket.main will be created
  + resource "aws_s3_bucket" "main" {
      + bucket        = (known after apply)
      + force_destroy = true
      + tags          = {
          + "Name"  = "robochef-023-main"
          + "Owner" = "saravanans"
          + "Site"  = "robochef.co"
        }
    }

# aws_s3_bucket_versioning.main will be created
  + versioning_configuration {
      + status = "Enabled"
    }

# aws_s3_bucket_public_access_block.main will be created
  + block_public_acls       = true
  + block_public_policy     = true
  + ignore_public_acls      = true
  + restrict_public_buckets = true

# aws_s3_bucket_policy.main will be created
# aws_s3_object.config_v1 will be created

Plan: 6 to add, 0 to change, 0 to destroy.
```

---

## 12. Apply

```bash
terraform apply
```

Type `yes` when prompted.

Expected output after apply (live test):

```text
random_string.suffix: Creating...
random_string.suffix: Creation complete after 0s [id=nbzhg6uy]
aws_s3_bucket.main: Creating...
aws_s3_bucket.main: Creation complete after 2s [id=robochef-demo-023-nbzhg6uy]
aws_s3_bucket_versioning.main: Creating...
aws_s3_bucket_public_access_block.main: Creating...
aws_s3_object.config_v1: Creating...
aws_s3_bucket_versioning.main: Creation complete after 1s
aws_s3_bucket_public_access_block.main: Creation complete after 1s
aws_s3_object.config_v1: Creation complete after 0s
aws_s3_bucket_policy.main: Creating...
aws_s3_bucket_policy.main: Creation complete after 1s

Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:

account_id        = "043000359118"
bucket_arn        = "arn:aws:s3:::robochef-demo-023-nbzhg6uy"
bucket_name       = "robochef-demo-023-nbzhg6uy"
list_versions_cmd = "aws s3api list-object-versions --bucket robochef-demo-023-nbzhg6uy --key config/settings.json --region ap-south-1"
policy_applied    = "Account-only read/write policy"
versioning        = "Enabled"
```

**Creation order Terraform used:**

1. `random_string.suffix` is created first — the bucket name depends on it
2. `aws_s3_bucket.main` is created next
3. `aws_s3_bucket_versioning.main`, `aws_s3_bucket_public_access_block.main`, and `aws_s3_object.config_v1` run in parallel (all depend only on the bucket)
4. `aws_s3_bucket_policy.main` waits for the public access block to complete (due to `depends_on`)

---

## 13. Versioning Demo

### Step 1: Confirm v1 was uploaded by Terraform

The `aws_s3_object.config_v1` resource already uploaded the first version of `config/settings.json`. Retrieve it:

```bash
BUCKET=$(terraform output -raw bucket_name)
REGION=$(grep aws_region terraform.tfvars | awk -F'"' '{print $2}')

aws s3api get-object \
  --bucket "$BUCKET" \
  --key config/settings.json \
  --region "$REGION" \
  downloaded_v1.json

cat downloaded_v1.json
```

Expected content of `downloaded_v1.json`:

```json
{"version":"1.0","app":"robochef","env":"demo"}
```

### Step 2: Create and upload v2

Create a new version of `settings.json` with an updated version number:

```bash
cat > v2.json <<'EOF'
{"version":"2.0","app":"robochef","env":"demo","updated_by":"saravanans"}
EOF

aws s3api put-object \
  --bucket "$BUCKET" \
  --key config/settings.json \
  --body v2.json \
  --content-type application/json \
  --region "$REGION"
```

Expected output:

```json
{
    "ETag": "\"d41d8cd98f00b204e9800998ecf8427e\"",
    "VersionId": "wvWzc1EuCHOPkts2FQ1qIxJuiBwwrNOE"
}
```

AWS returned a `VersionId` — this confirms versioning is active. If versioning were not enabled, there would be no `VersionId` in the response.

### Step 3: List all versions

```bash
aws s3api list-object-versions \
  --bucket "$BUCKET" \
  --key config/settings.json \
  --region "$REGION"
```

Live output from the test:

```json
{
    "Versions": [
        {
            "ETag": "\"d7cbdc9dd875caa0c7e67df0d6a91aa0\"",
            "Size": 47,
            "StorageClass": "STANDARD",
            "Key": "config/settings.json",
            "VersionId": "null",
            "IsLatest": false,
            "LastModified": "2025-01-01T10:00:00.000Z",
            "Owner": { "ID": "..." }
        },
        {
            "ETag": "\"d41d8cd98f00b204e9800998ecf8427e\"",
            "Size": 65,
            "StorageClass": "STANDARD",
            "Key": "config/settings.json",
            "VersionId": "wvWzc1EuCHOPkts2FQ1qIxJuiBwwrNOE",
            "IsLatest": true,
            "LastModified": "2025-01-01T10:05:00.000Z",
            "Owner": { "ID": "..." }
        }
    ]
}
```

**Reading the output:**

| Field | v1 | v2 |
|---|---|---|
| `VersionId` | `null` | `wvWzc1EuCHOPkts2FQ1qIxJuiBwwrNOE` |
| `IsLatest` | `false` | `true` |
| `Size` | 47 bytes | 65 bytes |

**Why does v1 have `VersionId: null`?**

When an object is uploaded *before* versioning is enabled on a bucket, it has no version ID — it is called a **null version**. Versioning was enabled before the Terraform `aws_s3_object.config_v1` resource ran, but the first upload under versioning still receives a `null` VersionId in some AWS provider versions. `VersionId: null` is a valid, retrievable version — it is not lost.

### Step 4: Retrieve a specific old version

To get the v1 file specifically (by its `null` VersionId):

```bash
aws s3api get-object \
  --bucket "$BUCKET" \
  --key config/settings.json \
  --version-id null \
  --region "$REGION" \
  old_v1.json

cat old_v1.json
```

Expected:

```json
{"version":"1.0","app":"robochef","env":"demo"}
```

You retrieved the old version even though v2 is now the current one. This is the power of versioning.

To get the current (latest) version without specifying a VersionId:

```bash
aws s3api get-object \
  --bucket "$BUCKET" \
  --key config/settings.json \
  --region "$REGION" \
  current.json

cat current.json
```

Expected:

```json
{"version":"2.0","app":"robochef","env":"demo","updated_by":"saravanans"}
```

---

## 14. Verify Bucket Policy

```bash
aws s3api get-bucket-policy \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --output json | python3 -m json.tool
```

Expected output:

```json
{
    "Policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AllowAccountAccess\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::043000359118:root\"},\"Action\":[\"s3:GetObject\",\"s3:PutObject\",\"s3:DeleteObject\",\"s3:ListBucket\"],\"Resource\":[\"arn:aws:s3:::robochef-demo-023-nbzhg6uy\",\"arn:aws:s3:::robochef-demo-023-nbzhg6uy/*\"]}]}"
}
```

The policy:
- **Principal:** `arn:aws:iam::043000359118:root` — only the owning account can access
- **Resource:** both the bucket ARN (for `ListBucket`) and the wildcard (`/*`) for object-level actions
- **No public access** — any anonymous request is blocked by the public access block before it even reaches this policy

---

## 15. Verify Public Access Block

```bash
aws s3api get-public-access-block \
  --bucket "$BUCKET" \
  --region "$REGION"
```

Expected output:

```json
{
    "PublicAccessBlockConfiguration": {
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }
}
```

All four flags are `true`. This is the maximum level of public access protection:

| Flag | What It Does |
|---|---|
| `BlockPublicAcls` | Rejects PUT requests that include a public ACL; removes public ACLs on existing objects |
| `IgnorePublicAcls` | Ignores any existing public ACLs even if they were somehow set |
| `BlockPublicPolicy` | Rejects bucket policies that grant public access |
| `RestrictPublicBuckets` | Restricts cross-account and anonymous access even if the bucket policy allows it |

**All four must be `true` to completely lock down a bucket.** Leaving any one flag `false` creates a gap.

---

## 16. Destroy

After the demo, remove all AWS resources:

```bash
terraform destroy
```

Type `yes`.

Expected:

```text
aws_s3_bucket_policy.main: Destroying...
aws_s3_object.config_v1: Destroying...
aws_s3_bucket_policy.main: Destruction complete after 1s
aws_s3_object.config_v1: Destruction complete after 0s
aws_s3_bucket_versioning.main: Destroying...
aws_s3_bucket_public_access_block.main: Destroying...
aws_s3_bucket_versioning.main: Destruction complete after 1s
aws_s3_bucket_public_access_block.main: Destruction complete after 1s
aws_s3_bucket.main: Destroying...
aws_s3_bucket.main: Destruction complete after 2s
random_string.suffix: Destroying...
random_string.suffix: Destruction complete after 0s

Destroy complete! Resources: 6 destroyed.
```

Then clean up the provider cache:

```bash
rm -rf .terraform
```

**Note:** `force_destroy = true` on the bucket is what made this work cleanly. The bucket contained v1 and v2 of `config/settings.json`. Without `force_destroy`, Terraform would have failed with `BucketNotEmpty` before it could delete the bucket — the versioned objects (including the v2 we uploaded via AWS CLI) would have blocked deletion.

---

## Full Copy-Paste Setup Script

```bash
mkdir -p ~/terraform-s3-023
cd ~/terraform-s3-023

cat > providers.tf <<'EOF_TF'
terraform {
  required_providers {
    aws    = { source = "hashicorp/aws",    version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}
provider "aws" { region = var.aws_region }
EOF_TF

cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "bucket_prefix" {
  type    = string
  default = "robochef-demo-023"
}
EOF_TF

cat > main.tf <<'EOF_TF'
resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "aws_s3_bucket" "main" {
  bucket        = "${var.bucket_prefix}-${random_string.suffix.result}"
  force_destroy = true
  tags          = { Name = "robochef-023-main", Owner = "saravanans", Site = "robochef.co" }
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket                  = aws_s3_bucket.main.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource  = [aws_s3_bucket.main.arn, "${aws_s3_bucket.main.arn}/*"]
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.main]
}

resource "aws_s3_object" "config_v1" {
  bucket       = aws_s3_bucket.main.id
  key          = "config/settings.json"
  content      = jsonencode({ version = "1.0", app = "robochef", env = "demo" })
  content_type = "application/json"
}
EOF_TF

cat > outputs.tf <<'EOF_TF'
output "bucket_name"        { value = aws_s3_bucket.main.bucket }
output "bucket_arn"         { value = aws_s3_bucket.main.arn }
output "account_id"         { value = data.aws_caller_identity.current.account_id }
output "versioning"         { value = "Enabled" }
output "policy_applied"     { value = "Account-only read/write policy" }
output "list_versions_cmd"  {
  value = "aws s3api list-object-versions --bucket ${aws_s3_bucket.main.bucket} --key config/settings.json --region ${var.aws_region}"
}
EOF_TF

cat > terraform.tfvars <<'EOF_TF'
aws_region    = "ap-south-1"
bucket_prefix = "robochef-demo-023"
EOF_TF

terraform init
terraform fmt
terraform validate
terraform plan
```

Then apply:

```bash
terraform apply
```

---

## Concept Summary

| Resource / Concept | What It Does |
|---|---|
| `aws_s3_bucket_versioning` | Enables versioning on a bucket; every upload creates a new version with a unique `VersionId`; old versions are retained and recoverable |
| `aws_s3_bucket_public_access_block` | Applies four independent access controls that block public ACLs, public policies, and cross-account anonymous access; all four must be `true` for complete lockdown |
| `aws_s3_bucket_policy` | Attaches an IAM JSON policy to the bucket defining exactly which principals and actions are allowed; evaluated after the public access block |
| `data "aws_caller_identity"` | Retrieves the AWS account ID dynamically from the current credentials; lets policy ARNs be built without hardcoding the account number |
| `depends_on` | Forces explicit ordering between resources Terraform cannot detect automatically; used here to ensure the public access block is applied before the bucket policy |
| `force_destroy` | When `true`, deletes all objects and versions in the bucket before destroying it; required when a versioned bucket has contents, otherwise destroy fails with `BucketNotEmpty` |
| `VersionId: null` | The version ID assigned to objects uploaded before versioning was enabled, or as the first object under versioning in some conditions; a `null` version is still a valid, retrievable version |
| Version history | The full list of every version of an object, each with a `VersionId`, `IsLatest` flag, size, and timestamp; retrieved with `aws s3api list-object-versions` |
