# 017 — Terraform AWS S3 Bucket, Object PUT and GET

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~20 minutes

## Topic

This demo shows how to use **Terraform** to:

1. Create an S3 bucket with a globally unique name using `random_string`
2. Enable versioning on the bucket using `aws_s3_bucket_versioning`
3. Upload two objects to the bucket using `aws_s3_object` (PUT)
4. Read back an object's content during the same apply using `data "aws_s3_object"` (GET)
5. Output the bucket name, ARN, ETag, and read-back content
6. Download and list objects using the AWS CLI
7. Destroy all resources cleanly

**New concepts in this lab:**

- `random_string` — generates a suffix so bucket names are globally unique
- `aws_s3_object` — uploads file content directly from Terraform (no local files needed)
- `data "aws_s3_object"` — reads an object back from S3 within the same apply
- `jsonencode()` — converts a Terraform map to a JSON string inline
- `etag` — the MD5 hash of an object, useful for verifying integrity

---

## What Terraform Creates

```text
random_string.suffix              → generates an 8-character lowercase suffix
aws_s3_bucket.demo                → S3 bucket named terraform-017-demo-<suffix>
aws_s3_bucket_versioning.demo     → enables versioning on the bucket
aws_s3_object.hello               → uploads hello.txt with plain text content
aws_s3_object.config              → uploads config/app.json with JSON content
data.aws_s3_object.read_hello     → reads hello.txt back from S3 (same apply)
```

**Plan: 5 to add, 0 to change, 0 to destroy.**

---

## 1. Create Project Folder

```bash
mkdir -p ~/terraform-aws-s3-017-demo
cd ~/terraform-aws-s3-017-demo
```

---

## 2. Check Your AWS Region

```bash
aws configure get region
aws sts get-caller-identity
```

Update `terraform.tfvars` to match your configured region. This lab was tested with `ap-south-1`.

---

## 3. Create Terraform Files

Create the following files:

```text
providers.tf
variables.tf
main.tf
outputs.tf
terraform.tfvars
```

---

## 4. providers.tf

Two providers are required — `aws` and `random`:

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

| Provider | Purpose |
|----------|---------|
| `hashicorp/aws` | Creates S3 bucket, versioning, and objects |
| `hashicorp/random` | Generates a random suffix for the bucket name |

---

## 5. variables.tf

```bash
cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name (must be lowercase)"
  type        = string
  default     = "terraform-017-demo"
}
EOF_TF
```

Only two variables are needed. The full bucket name is assembled in `main.tf` by combining `bucket_prefix` with the random suffix.

---

## 6. main.tf

```bash
cat > main.tf <<'EOF_TF'
resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "aws_s3_bucket" "demo" {
  bucket = "${var.bucket_prefix}-${random_string.suffix.result}"

  tags = {
    Name = "terraform-017-demo"
  }
}

resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "hello" {
  bucket       = aws_s3_bucket.demo.id
  key          = "hello.txt"
  content      = "Hello from Terraform! Bucket: ${aws_s3_bucket.demo.bucket}"
  content_type = "text/plain"
}

resource "aws_s3_object" "config" {
  bucket       = aws_s3_bucket.demo.id
  key          = "config/app.json"
  content      = jsonencode({ env = "demo", version = "1.0", tool = "terraform" })
  content_type = "application/json"
}

data "aws_s3_object" "read_hello" {
  bucket = aws_s3_bucket.demo.id
  key    = aws_s3_object.hello.key

  depends_on = [aws_s3_object.hello]
}
EOF_TF
```

**Key connections in main.tf:**

```text
random_string.suffix.result           → aws_s3_bucket.demo.bucket (unique name)
aws_s3_bucket.demo.id                 → aws_s3_bucket_versioning.demo.bucket
aws_s3_bucket.demo.id                 → aws_s3_object.hello.bucket
aws_s3_bucket.demo.id                 → aws_s3_object.config.bucket
aws_s3_bucket.demo.bucket             → aws_s3_object.hello.content (embedded in text)
aws_s3_object.hello.key               → data.aws_s3_object.read_hello.key
```

---

## 7. Key Concept: `random_string` for a Globally Unique Bucket Name

S3 bucket names are **global across all AWS accounts**. A bucket named `terraform-017-demo` will conflict if anyone else has already created it.

`random_string` generates a short suffix (e.g., `zdttyh9q`) appended to your prefix:

```hcl
resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

bucket = "${var.bucket_prefix}-${random_string.suffix.result}"
# → terraform-017-demo-zdttyh9q
```

Setting `upper = false` and `special = false` keeps the suffix lowercase and alphanumeric only — required for valid S3 bucket names.

---

## 8. Key Concept: `aws_s3_object` for PUT (Upload)

`aws_s3_object` uploads content directly into S3 — no local file needed. Content is defined inline using the `content` argument:

```hcl
resource "aws_s3_object" "hello" {
  bucket       = aws_s3_bucket.demo.id
  key          = "hello.txt"
  content      = "Hello from Terraform! Bucket: ${aws_s3_bucket.demo.bucket}"
  content_type = "text/plain"
}
```

For JSON content, use `jsonencode()` to convert a Terraform map:

```hcl
resource "aws_s3_object" "config" {
  bucket       = aws_s3_bucket.demo.id
  key          = "config/app.json"
  content      = jsonencode({ env = "demo", version = "1.0", tool = "terraform" })
  content_type = "application/json"
}
```

`jsonencode()` produces: `{"env":"demo","tool":"terraform","version":"1.0"}`

The `key` is the object path inside the bucket. Using `config/app.json` creates a logical folder called `config/` (S3 has no real folders — the `/` is part of the key name).

---

## 9. Key Concept: `data "aws_s3_object"` for GET (Read Back)

`data "aws_s3_object"` reads an existing object from S3 and exposes its content via the `body` attribute. This allows Terraform to verify what was uploaded during the same apply:

```hcl
data "aws_s3_object" "read_hello" {
  bucket = aws_s3_bucket.demo.id
  key    = aws_s3_object.hello.key

  depends_on = [aws_s3_object.hello]
}
```

`depends_on = [aws_s3_object.hello]` tells Terraform to wait until the object is uploaded before reading it back. Without this, the data source might run before the object exists.

The content is then surfaced as an output:

```hcl
output "hello_content_read_back" {
  value = data.aws_s3_object.read_hello.body
}
```

---

## 10. outputs.tf

```bash
cat > outputs.tf <<'EOF_TF'
output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.demo.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.demo.arn
}

output "bucket_region" {
  description = "S3 bucket region"
  value       = aws_s3_bucket.demo.region
}

output "hello_object_key" {
  value = aws_s3_object.hello.key
}

output "hello_object_etag" {
  description = "ETag (MD5) of hello.txt"
  value       = aws_s3_object.hello.etag
}

output "hello_content_read_back" {
  description = "Content of hello.txt read back via data source"
  value       = data.aws_s3_object.read_hello.body
}

output "config_object_key" {
  value = aws_s3_object.config.key
}

output "aws_cli_get_command" {
  value = "aws s3 cp s3://${aws_s3_bucket.demo.bucket}/hello.txt ./hello_downloaded.txt"
}
EOF_TF
```

---

## 11. terraform.tfvars

```bash
cat > terraform.tfvars <<'EOF_TF'
aws_region    = "ap-south-1"
bucket_prefix = "terraform-017-demo"
EOF_TF
```

Update `aws_region` to match your configured region (`aws configure get region`).

---

## 12. Initialize Terraform

Confirm your AWS region first:

```bash
aws configure get region
```

Then initialize:

```bash
terraform init
```

Expected output:

```text
- Installing hashicorp/aws v6.x.x...
- Installing hashicorp/random v3.x.x...

Terraform has been successfully initialized!
```

Both providers are downloaded and installed.

> **Note:** If you see a lock file conflict, run `terraform init -upgrade`.

---

## 13. Format and Validate

```bash
terraform fmt
terraform validate
```

Expected:

```text
Success! The configuration is valid.
```

---

## 14. Plan

```bash
terraform plan
```

Expected plan output:

```text
# random_string.suffix will be created
  + resource "random_string" "suffix" {
      + length  = 8
      + result  = (known after apply)
      + special = false
      + upper   = false
    }

# aws_s3_bucket.demo will be created
  + resource "aws_s3_bucket" "demo" {
      + bucket = (known after apply)
      + arn    = (known after apply)
    }

# aws_s3_bucket_versioning.demo will be created
  + resource "aws_s3_bucket_versioning" "demo" {
      + versioning_configuration {
          + status = "Enabled"
        }
    }

# aws_s3_object.hello will be created
  + resource "aws_s3_object" "hello" {
      + bucket  = (known after apply)
      + key     = "hello.txt"
      + content = (known after apply)
    }

# aws_s3_object.config will be created
  + resource "aws_s3_object" "config" {
      + bucket  = (known after apply)
      + key     = "config/app.json"
    }

Plan: 5 to add, 0 to change, 0 to destroy.
```

Five resources will be created: `random_string`, `aws_s3_bucket`, `aws_s3_bucket_versioning`, and two `aws_s3_object` resources. The data source is not counted in the plan total — it reads during apply.

---

## 15. Apply

```bash
terraform apply
```

Type `yes` when prompted.

Expected output after apply:

```text
random_string.suffix: Creating...
random_string.suffix: Creation complete after 0s [id=zdttyh9q]
aws_s3_bucket.demo: Creating...
aws_s3_bucket.demo: Creation complete after 2s [id=terraform-017-demo-zdttyh9q]
aws_s3_bucket_versioning.demo: Creating...
aws_s3_bucket_versioning.demo: Creation complete after 1s [id=terraform-017-demo-zdttyh9q]
aws_s3_object.hello: Creating...
aws_s3_object.config: Creating...
aws_s3_object.hello: Creation complete after 0s [id=hello.txt]
aws_s3_object.config: Creation complete after 0s [id=config/app.json]
data.aws_s3_object.read_hello: Reading...
data.aws_s3_object.read_hello: Read complete after 0s [id=hello.txt]

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

aws_cli_get_command      = "aws s3 cp s3://terraform-017-demo-zdttyh9q/hello.txt ./hello_downloaded.txt"
bucket_arn               = "arn:aws:s3:::terraform-017-demo-zdttyh9q"
bucket_name              = "terraform-017-demo-zdttyh9q"
bucket_region            = "ap-south-1"
config_object_key        = "config/app.json"
hello_content_read_back  = "Hello from Terraform! Bucket: terraform-017-demo-zdttyh9q"
hello_object_etag        = "3f3720794048ce90220074e2489e9f2d"
hello_object_key         = "hello.txt"
```

**Creation order:**

1. `random_string.suffix` — no dependencies, runs first
2. `aws_s3_bucket.demo` — waits for `random_string` (needs the suffix for the bucket name)
3. `aws_s3_bucket_versioning.demo` — waits for the bucket
4. `aws_s3_object.hello` and `aws_s3_object.config` — wait for the bucket, run in parallel
5. `data.aws_s3_object.read_hello` — waits for `aws_s3_object.hello` via `depends_on`

Notice `hello_content_read_back` shows the exact content uploaded — Terraform read it back from S3 in the same apply run.

---

## 16. AWS CLI GET Operations

After apply, use the AWS CLI to interact with your bucket directly.

### Download an Object

Use the `aws_cli_get_command` output to download `hello.txt`:

```bash
aws s3 cp s3://terraform-017-demo-zdttyh9q/hello.txt ./hello_downloaded.txt
```

Expected:

```text
download: s3://terraform-017-demo-zdttyh9q/hello.txt to ./hello_downloaded.txt
```

Verify the content:

```bash
cat ./hello_downloaded.txt
```

Expected:

```text
Hello from Terraform! Bucket: terraform-017-demo-zdttyh9q
```

### List All Objects Recursively

```bash
aws s3 ls s3://terraform-017-demo-zdttyh9q/ --recursive
```

Expected:

```text
2025-05-21 10:xx:xx         57 config/app.json
2025-05-21 10:xx:xx         55 hello.txt
```

Both objects are visible — `hello.txt` at the root and `config/app.json` under the `config/` prefix.

### Stream Object Content to stdout

To view an object without saving it to disk, stream it with `-`:

```bash
aws s3 cp s3://terraform-017-demo-zdttyh9q/hello.txt -
```

Expected:

```text
Hello from Terraform! Bucket: terraform-017-demo-zdttyh9q
```

To view the JSON config object:

```bash
aws s3 cp s3://terraform-017-demo-zdttyh9q/config/app.json -
```

Expected:

```text
{"env":"demo","tool":"terraform","version":"1.0"}
```

### Get Outputs Again Later

```bash
terraform output
terraform output -raw bucket_name
terraform output -raw hello_content_read_back
terraform output -raw aws_cli_get_command
```

---

## 17. Destroy Resources

After the demo, delete all AWS resources to avoid charges:

```bash
terraform destroy
```

Type `yes` when prompted.

Expected:

```text
aws_s3_object.hello: Destroying...
aws_s3_object.config: Destroying...
aws_s3_object.hello: Destruction complete after 0s
aws_s3_object.config: Destruction complete after 0s
aws_s3_bucket_versioning.demo: Destroying...
aws_s3_bucket_versioning.demo: Destruction complete after 0s
aws_s3_bucket.demo: Destroying...
aws_s3_bucket.demo: Destruction complete after 1s
random_string.suffix: Destroying...
random_string.suffix: Destruction complete after 0s

Destroy complete! Resources: 5 destroyed.
```

Then clean up the provider cache:

```bash
rm -rf .terraform
```

---

## 18. Full Copy-Paste Setup Script

Use this to create all files and run the workflow in one go.

```bash
mkdir -p ~/terraform-aws-s3-017-demo
cd ~/terraform-aws-s3-017-demo

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

cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name (must be lowercase)"
  type        = string
  default     = "terraform-017-demo"
}
EOF_TF

cat > main.tf <<'EOF_TF'
resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "aws_s3_bucket" "demo" {
  bucket = "${var.bucket_prefix}-${random_string.suffix.result}"

  tags = {
    Name = "terraform-017-demo"
  }
}

resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "hello" {
  bucket       = aws_s3_bucket.demo.id
  key          = "hello.txt"
  content      = "Hello from Terraform! Bucket: ${aws_s3_bucket.demo.bucket}"
  content_type = "text/plain"
}

resource "aws_s3_object" "config" {
  bucket       = aws_s3_bucket.demo.id
  key          = "config/app.json"
  content      = jsonencode({ env = "demo", version = "1.0", tool = "terraform" })
  content_type = "application/json"
}

data "aws_s3_object" "read_hello" {
  bucket = aws_s3_bucket.demo.id
  key    = aws_s3_object.hello.key

  depends_on = [aws_s3_object.hello]
}
EOF_TF

cat > outputs.tf <<'EOF_TF'
output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.demo.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.demo.arn
}

output "bucket_region" {
  description = "S3 bucket region"
  value       = aws_s3_bucket.demo.region
}

output "hello_object_key" {
  value = aws_s3_object.hello.key
}

output "hello_object_etag" {
  description = "ETag (MD5) of hello.txt"
  value       = aws_s3_object.hello.etag
}

output "hello_content_read_back" {
  description = "Content of hello.txt read back via data source"
  value       = data.aws_s3_object.read_hello.body
}

output "config_object_key" {
  value = aws_s3_object.config.key
}

output "aws_cli_get_command" {
  value = "aws s3 cp s3://${aws_s3_bucket.demo.bucket}/hello.txt ./hello_downloaded.txt"
}
EOF_TF

MY_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")

cat > terraform.tfvars <<EOF_TF
aws_region    = "${MY_REGION}"
bucket_prefix = "terraform-017-demo"
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

After testing:

```bash
terraform destroy
rm -rf .terraform
```

---

## 19. Final File Structure

```text
terraform-aws-s3-017-demo/
├── main.tf
├── outputs.tf
├── providers.tf
├── terraform.tfvars
├── variables.tf
├── .terraform.lock.hcl
├── terraform.tfstate
└── terraform.tfstate.backup
```

---

## 20. Concept Summary

| Resource / Concept | What It Does |
|---|---|
| `aws_s3_bucket` | Creates the S3 bucket with a given name and optional tags |
| `aws_s3_bucket_versioning` | Enables versioning so S3 keeps previous object versions |
| `aws_s3_object` | Uploads content to S3 directly from Terraform (PUT operation) |
| `data "aws_s3_object"` | Reads an object from S3 during apply and exposes its content as `body` (GET operation) |
| `random_string` | Generates a random suffix to make bucket names globally unique |
| `jsonencode()` | Converts a Terraform map or object to a JSON string inline |
| `etag` | MD5 hash of the uploaded object content — useful for integrity checks |
| `depends_on` | Forces the data source to wait until the object resource is created |
| `content_type` | Sets the MIME type of the object (`text/plain`, `application/json`, etc.) |
| `aws s3 cp` | AWS CLI command to download or upload S3 objects |
| `aws s3 ls --recursive` | Lists all objects in a bucket, including those under prefixes |
