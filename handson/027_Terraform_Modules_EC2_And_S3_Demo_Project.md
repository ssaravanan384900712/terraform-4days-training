# 027 — Terraform Modules: EC2 + S3 Demo Project

**By: Saravanan Sundaramoorthy**
**Environment:** AWS ap-south-1 (Mumbai)
**Time to complete:** ~20 minutes

---

## Topic

| Concept | What it means |
|---------|--------------|
| **Terraform Module** | A folder of `.tf` files used as a reusable building block |
| **`source` argument** | Tells Terraform where to find the module (local path, Git, registry) |
| **Module inputs** | Variables declared in the module's `variables.tf` |
| **Module outputs** | Values exposed via `outputs.tf`, referenced as `module.<name>.<output>` |
| **No provider in module** | Modules inherit the provider from the root; never declare `provider {}` in a module |
| **`merge()` for tags** | Combines module-default tags with caller-supplied tags without overwriting either |

This lab builds on labs **025** (EC2 module) and **026** (S3 module) and shows how a single calling project can use both modules together. The module files live at `~/terraform-modules/` and are reused by any project that references them.

---

## Architecture

```
~/terraform-modules/
├── ec2-instance/          ← Module 025
│   ├── main.tf            (tls_private_key + aws_key_pair + aws_security_group + aws_instance)
│   ├── variables.tf
│   └── outputs.tf
└── s3-bucket/             ← Module 026
    ├── main.tf            (aws_s3_bucket + versioning + public_access_block)
    ├── variables.tf
    └── outputs.tf

~/terraform-aws-modules-027-demo/   ← this lab (calling project)
├── providers.tf
├── variables.tf
├── main.tf                (random_string + module.web_server + module.app_bucket + module.chillbot_bucket)
├── outputs.tf
└── terraform.tfvars
```

---

## What Terraform Creates

| Resource | Description |
|---------|-------------|
| `random_string.suffix` | 6-char lowercase suffix for unique S3 bucket names |
| `module.web_server` → 5 resources | tls_private_key, local_sensitive_file, aws_key_pair, aws_security_group, aws_instance |
| `module.app_bucket` → 3 resources | aws_s3_bucket (versioning ON), aws_s3_bucket_versioning, aws_s3_bucket_public_access_block |
| `module.chillbot_bucket` → 3 resources | aws_s3_bucket (versioning OFF), aws_s3_bucket_versioning, aws_s3_bucket_public_access_block |
| **Total** | **12 resources** |

---

## Step 1 — Create the module directories (if not already done)

The module directories should already exist from labs 025 and 026. Verify:

```bash
ls ~/terraform-modules/ec2-instance/
ls ~/terraform-modules/s3-bucket/
```

Expected output:
```
main.tf  outputs.tf  variables.tf
main.tf  outputs.tf  variables.tf
```

---

## Step 2 — Module files reference

### ec2-instance module (`~/terraform-modules/ec2-instance/`)

#### `main.tf`

```hcl
terraform {
  required_providers {
    aws   = { source = "hashicorp/aws",   version = "~> 6.0" }
    tls   = { source = "hashicorp/tls",   version = "~> 4.0" }
    local = { source = "hashicorp/local", version = "~> 2.0" }
  }
}

resource "tls_private_key" "this" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.this.private_key_openssh
  filename        = pathexpand(var.private_key_path)
  file_permission = "0600"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_key_pair" "this" {
  key_name   = "${var.instance_name}-key"
  public_key = tls_private_key.this.public_key_openssh
}

resource "aws_security_group" "ssh" {
  name        = "${var.instance_name}-ssh-sg"
  description = "Allow SSH"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({ Name = "${var.instance_name}-ssh-sg" }, var.tags)
}

resource "aws_instance" "this" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.this.key_name
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  associate_public_ip_address = true

  tags = merge({ Name = var.instance_name }, var.tags)
}
```

#### `variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}
variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
}
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}
variable "private_key_path" {
  description = "Path where the generated private key is saved"
  type        = string
  default     = "~/.ssh/terraform-module-ec2"
}
variable "allowed_ssh_cidr" {
  description = "CIDR allowed for SSH"
  type        = string
  default     = "0.0.0.0/0"
}
variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
```

#### `outputs.tf`

```hcl
output "instance_id"      { value = aws_instance.this.id }
output "public_ip"        { value = aws_instance.this.public_ip }
output "ami_id"           { value = data.aws_ami.ubuntu.id }
output "private_key_path" { value = local_sensitive_file.private_key.filename }
output "ssh_command"      { value = "ssh -i ${pathexpand(var.private_key_path)} ubuntu@${aws_instance.this.public_ip}" }
```

---

### s3-bucket module (`~/terraform-modules/s3-bucket/`)

#### `main.tf`

```hcl
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
```

#### `variables.tf`

```hcl
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
```

#### `outputs.tf`

```hcl
output "bucket_name"       { value = aws_s3_bucket.this.bucket }
output "bucket_arn"        { value = aws_s3_bucket.this.arn }
output "bucket_id"         { value = aws_s3_bucket.this.id }
output "versioning_status" { value = var.enable_versioning ? "Enabled" : "Suspended" }
```

---

## Step 3 — Create the demo project folder

```bash
mkdir -p ~/terraform-aws-modules-027-demo
cd ~/terraform-aws-modules-027-demo
```

---

## Step 4 — Write all project files

### `providers.tf`

```bash
cat > providers.tf <<'EOF_TF'
terraform {
  required_providers {
    aws    = { source = "hashicorp/aws",    version = "~> 6.0" }
    tls    = { source = "hashicorp/tls",    version = "~> 4.0" }
    local  = { source = "hashicorp/local",  version = "~> 2.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}
provider "aws" { region = var.aws_region }
EOF_TF
```

### `variables.tf`

```bash
cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  type    = string
  default = "ap-south-1"
}
EOF_TF
```

### `main.tf`

```bash
cat > main.tf <<'EOF_TF'
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

module "web_server" {
  source           = "../terraform-modules/ec2-instance"
  instance_name    = "robochef-web"
  instance_type    = "t3.micro"
  private_key_path = "~/.ssh/terraform-027-robochef"
  tags = {
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}

module "app_bucket" {
  source            = "../terraform-modules/s3-bucket"
  bucket_name       = "robochef-app-${random_string.suffix.result}"
  enable_versioning = true
  force_destroy     = true
  tags = {
    Owner = "saravanans"
    Site  = "robochef.co"
  }
}

module "chillbot_bucket" {
  source            = "../terraform-modules/s3-bucket"
  bucket_name       = "chillbotindia-app-${random_string.suffix.result}"
  enable_versioning = false
  force_destroy     = true
  tags = {
    Owner = "saravanans"
    Site  = "chillbotindia.com"
  }
}
EOF_TF
```

**Key points about `main.tf`:**
- `source = "../terraform-modules/ec2-instance"` — relative path to the local module directory
- Both S3 buckets share the same `random_string.suffix.result`, so their names always have the same suffix
- `enable_versioning = true` for robochef, `false` for chillbot — the module's conditional handles the difference
- `force_destroy = true` for clean lab teardown

### `outputs.tf`

```bash
cat > outputs.tf <<'EOF_TF'
output "web_instance_id"    { value = module.web_server.instance_id }
output "web_public_ip"      { value = module.web_server.public_ip }
output "web_ssh_command"    { value = module.web_server.ssh_command }
output "app_bucket_name"    { value = module.app_bucket.bucket_name }
output "app_bucket_arn"     { value = module.app_bucket.bucket_arn }
output "chillbot_bucket_name" { value = module.chillbot_bucket.bucket_name }
output "app_versioning"     { value = module.app_bucket.versioning_status }
output "chillbot_versioning"  { value = module.chillbot_bucket.versioning_status }
EOF_TF
```

Output references follow the pattern `module.<module_label>.<output_name>`.

### `terraform.tfvars`

```bash
cat > terraform.tfvars <<'EOF_TF'
aws_region = "ap-south-1"
EOF_TF
```

---

## Step 5 — Init, Fmt, Validate, Plan, Apply

```bash
terraform init
```

Expected output (key lines):
```
Initializing modules...
- app_bucket in ../terraform-modules/s3-bucket
- chillbot_bucket in ../terraform-modules/s3-bucket
- web_server in ../terraform-modules/ec2-instance

Terraform has been successfully initialized!
```

> **Note:** `terraform init` must be re-run every time you add or change a `module` block.

```bash
terraform fmt
terraform validate
# Success! The configuration is valid.

terraform plan
# Plan: 12 to add, 0 to change, 0 to destroy.
```

```bash
terraform apply -auto-approve
```

Expected output:
```
module.web_server.tls_private_key.this: Creating...
random_string.suffix: Creating...
module.web_server.tls_private_key.this: Creation complete after 0s
random_string.suffix: Creation complete after 0s [id=86msok]
module.web_server.local_sensitive_file.private_key: Creation complete after 0s
module.web_server.aws_security_group.ssh: Creating...
module.app_bucket.aws_s3_bucket.this: Creating...
module.web_server.aws_key_pair.this: Creating...
module.chillbot_bucket.aws_s3_bucket.this: Creating...
module.web_server.aws_key_pair.this: Creation complete after 1s [id=robochef-web-key]
module.app_bucket.aws_s3_bucket.this: Creation complete after 1s [id=robochef-app-86msok]
module.chillbot_bucket.aws_s3_bucket.this: Creation complete after 1s [id=chillbotindia-app-86msok]
...
module.web_server.aws_instance.this: Creation complete after 12s [id=i-08e994374c544c09a]

Apply complete! Resources: 12 added, 0 changed, 0 destroyed.

Outputs:

app_bucket_arn       = "arn:aws:s3:::robochef-app-86msok"
app_bucket_name      = "robochef-app-86msok"
app_versioning       = "Enabled"
chillbot_bucket_name = "chillbotindia-app-86msok"
chillbot_versioning  = "Suspended"
web_instance_id      = "i-08e994374c544c09a"
web_public_ip        = "13.234.119.211"
web_ssh_command      = "ssh -i /home/saravanans/.ssh/terraform-027-robochef ubuntu@13.234.119.211"
```

---

## Step 6 — Verify

### SSH into the EC2 instance

```bash
ssh -i ~/.ssh/terraform-027-robochef -o StrictHostKeyChecking=no ubuntu@13.234.119.211
```

Expected:
```
SSH OK: ip-172-31-42-35 6.8.0-1053-aws
```

### Verify S3 buckets exist

```bash
aws s3 ls | grep -E "robochef|chillbot"
```

Expected:
```
2026-05-21 xx:xx:xx robochef-app-86msok
2026-05-21 xx:xx:xx chillbotindia-app-86msok
```

### Verify versioning status

```bash
aws s3api get-bucket-versioning --bucket robochef-app-86msok
# {"Status": "Enabled"}

aws s3api get-bucket-versioning --bucket chillbotindia-app-86msok
# {} (empty = Suspended)
```

---

## Key Concept 1 — Module source paths

```
source = "../terraform-modules/ec2-instance"
```

| Source type | Example |
|-------------|---------|
| Local path | `source = "../modules/ec2"` |
| Git HTTPS | `source = "git::https://github.com/org/repo.git//modules/ec2"` |
| Terraform Registry | `source = "terraform-aws-modules/ec2-instance/aws"` |
| S3 bucket | `source = "s3::https://s3.amazonaws.com/bucket/module.zip"` |

Local paths always start with `./` or `../`. Any other string is treated as a registry address.

---

## Key Concept 2 — No `provider {}` in modules

Modules **must not** have a `provider {}` block. The root module's provider configuration is automatically inherited. If a module declared its own provider, Terraform would create a second provider instance, potentially in a different region.

```hcl
# WRONG — do not do this inside a module
provider "aws" { region = "us-east-1" }  ← breaks caller's region setting

# CORRECT — module main.tf only declares required_providers (version constraints)
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
```

---

## Key Concept 3 — `merge()` for tags

```hcl
tags = merge({ Name = "${var.instance_name}-ssh-sg" }, var.tags)
```

`merge()` combines two maps. Values in later maps override earlier ones for duplicate keys. This lets the module set a default `Name` tag while the caller adds `Owner`, `Project`, etc. — without either overwriting the other.

---

## Key Concept 4 — Module outputs vs root outputs

Module outputs are referenced as `module.<label>.<output_name>`:

```hcl
# In root outputs.tf
output "web_public_ip" { value = module.web_server.public_ip }
#                                       ^^^^^^^^^^  ^^^^^^^^^^^
#                                       module label  output from module's outputs.tf
```

The module label (`web_server`) is the name given in the `module` block in `main.tf`, not the module directory name.

---

## Step 7 — Destroy

```bash
terraform destroy -auto-approve
rm -rf .terraform
```

The `force_destroy = true` on both S3 buckets ensures destroy succeeds even if objects were uploaded manually.

---

## Copy-paste script (full flow)

```bash
# Prerequisites: module files exist at ~/terraform-modules/ec2-instance/ and ~/terraform-modules/s3-bucket/
mkdir -p ~/terraform-aws-modules-027-demo
cd ~/terraform-aws-modules-027-demo

cat > providers.tf <<'EOF_TF'
terraform {
  required_providers {
    aws    = { source = "hashicorp/aws",    version = "~> 6.0" }
    tls    = { source = "hashicorp/tls",    version = "~> 4.0" }
    local  = { source = "hashicorp/local",  version = "~> 2.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}
provider "aws" { region = var.aws_region }
EOF_TF

cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  type    = string
  default = "ap-south-1"
}
EOF_TF

cat > main.tf <<'EOF_TF'
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

module "web_server" {
  source           = "../terraform-modules/ec2-instance"
  instance_name    = "robochef-web"
  instance_type    = "t3.micro"
  private_key_path = "~/.ssh/terraform-027-robochef"
  tags = {
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}

module "app_bucket" {
  source            = "../terraform-modules/s3-bucket"
  bucket_name       = "robochef-app-${random_string.suffix.result}"
  enable_versioning = true
  force_destroy     = true
  tags = {
    Owner = "saravanans"
    Site  = "robochef.co"
  }
}

module "chillbot_bucket" {
  source            = "../terraform-modules/s3-bucket"
  bucket_name       = "chillbotindia-app-${random_string.suffix.result}"
  enable_versioning = false
  force_destroy     = true
  tags = {
    Owner = "saravanans"
    Site  = "chillbotindia.com"
  }
}
EOF_TF

cat > outputs.tf <<'EOF_TF'
output "web_instance_id"      { value = module.web_server.instance_id }
output "web_public_ip"        { value = module.web_server.public_ip }
output "web_ssh_command"      { value = module.web_server.ssh_command }
output "app_bucket_name"      { value = module.app_bucket.bucket_name }
output "app_bucket_arn"       { value = module.app_bucket.bucket_arn }
output "chillbot_bucket_name" { value = module.chillbot_bucket.bucket_name }
output "app_versioning"       { value = module.app_bucket.versioning_status }
output "chillbot_versioning"  { value = module.chillbot_bucket.versioning_status }
EOF_TF

cat > terraform.tfvars <<'EOF_TF'
aws_region = "ap-south-1"
EOF_TF

terraform init
terraform fmt
terraform validate
terraform plan
terraform apply -auto-approve

# Verify
ssh -i ~/.ssh/terraform-027-robochef -o StrictHostKeyChecking=no ubuntu@$(terraform output -raw web_public_ip) 'echo "SSH OK"'
aws s3 ls | grep -E "robochef|chillbot"
aws s3api get-bucket-versioning --bucket $(terraform output -raw app_bucket_name)

# Cleanup
terraform destroy -auto-approve
rm -rf .terraform
```

---

## Concept Summary

| Concept | Key rule |
|---------|----------|
| Module source | Local path must start with `./` or `../`; anything else is a registry address |
| Provider in module | Never add `provider {}` to a module; modules inherit the root provider |
| `required_providers` in module | Declare version constraints so Terraform can pick a compatible version |
| Module inputs | Passed as arguments in the `module` block; maps to the module's `variable` blocks |
| Module outputs | Exposed via module's `outputs.tf`; referenced as `module.<label>.<output>` |
| `merge()` tags | Lets module set defaults while caller adds extra tags; no overwrites |
| `terraform init` | Must re-run after any change to `module` blocks |
| `random_string` suffix | Ensures globally unique S3 bucket names across both module calls |
| `force_destroy` | Must be `true` on S3 buckets when you want clean `terraform destroy` |
| Module reuse | Same `s3-bucket` module called twice with different arguments = two distinct buckets |
