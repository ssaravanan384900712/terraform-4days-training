# Lab 2.5 — Terraform State Management

Terraform state is the backbone of how Terraform maps your configuration to real-world resources. In this lab you will understand what state is and why it matters, configure a remote S3 backend with DynamoDB locking, enable encryption and versioning for state files, work with workspaces for environment isolation, implement directory-based isolation, use `terraform_remote_state` to share outputs between configurations, and import existing AWS resources into Terraform management.

---

## Prerequisites

- Terraform >= 1.6 installed
- AWS CLI configured
- An AWS account where you can create S3 buckets and DynamoDB tables

---

## Part 1 — What is Terraform State?

Terraform state (`terraform.tfstate`) is a JSON file that records the mapping between your HCL configuration and actual infrastructure resources.

### Purpose of State

| Purpose                    | Description                                                  |
|----------------------------|--------------------------------------------------------------|
| **Resource Mapping**       | Maps `aws_instance.web` to `i-0abc123def456`                |
| **Metadata Tracking**      | Stores resource dependencies for correct destroy ordering    |
| **Performance Cache**      | Avoids querying every resource on every plan                 |
| **Change Detection**       | Compares desired state (config) vs current state (state file)|

### Step 1: Examine a state file

```bash
mkdir -p ~/lab2.5-state && cd ~/lab2.5-state

# Create a minimal config
cat > main.tf <<'EOF'
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "example" {
  bucket_prefix = "lab25-state-demo-"

  tags = {
    Name = "state-demo"
  }
}
EOF

terraform init
terraform apply -auto-approve

# Examine the state file
cat terraform.tfstate | python3 -m json.tool | head -50
```

Expected structure (abbreviated):

```json
{
  "version": 4,
  "terraform_version": "1.6.x",
  "serial": 1,
  "lineage": "unique-uuid",
  "outputs": {},
  "resources": [
    {
      "mode": "managed",
      "type": "aws_s3_bucket",
      "name": "example",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "attributes": {
            "id": "lab25-state-demo-abc12345",
            "arn": "arn:aws:s3:::lab25-state-demo-abc12345",
            "bucket": "lab25-state-demo-abc12345",
            ...
          }
        }
      ]
    }
  ]
}
```

> **Warning:** State files contain **sensitive data** in plain text -- database passwords, API keys, and resource IDs. Never commit `terraform.tfstate` to version control. Always use a remote backend with encryption.

### Step 2: Clean up the demo

```bash
terraform destroy -auto-approve
rm -rf .terraform* terraform.tfstate*
```

---

## Part 2 — Remote State with S3 Backend

Storing state locally is fine for individual experimentation but breaks down in teams. A remote backend provides:

- **Shared access**: Everyone on the team reads/writes the same state
- **Locking**: Prevents concurrent modifications that corrupt state
- **Versioning**: Recover from accidental state corruption
- **Encryption**: Protect sensitive data at rest

### Step 3: Bootstrap the S3 backend infrastructure

First, create the S3 bucket and DynamoDB table that will store and lock your state. This is a chicken-and-egg problem -- we use a local backend to create the backend infrastructure.

```bash
mkdir -p ~/lab2.5-state/bootstrap && cd ~/lab2.5-state/bootstrap
```

Create `bootstrap.tf`:

```hcl
# bootstrap.tf
# Creates the S3 bucket and DynamoDB table for remote state storage
# This config itself uses LOCAL state (bootstrapping)

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# --- S3 Bucket for State Storage ---
resource "aws_s3_bucket" "terraform_state" {
  bucket = "lab25-terraform-state-${data.aws_caller_identity.current.account_id}"

  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name    = "terraform-state"
    Purpose = "Terraform remote state storage"
  }
}

# Enable versioning to recover from state corruption
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption by default
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- DynamoDB Table for State Locking ---
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-state-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name    = "terraform-state-locks"
    Purpose = "Terraform state locking"
  }
}

data "aws_caller_identity" "current" {}

# --- Outputs ---
output "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.terraform_state.arn
}

output "dynamodb_table_name" {
  description = "DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}
```

### Step 4: Apply the bootstrap

```bash
terraform init
terraform apply -auto-approve
```

Expected output:

```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

state_bucket_name = "lab25-terraform-state-123456789012"
dynamodb_table_name = "terraform-state-locks"
account_id = "123456789012"
```

> **Note the bucket name** -- you will need it in the next step.

---

## Part 3 — Configure S3 Backend

### Step 5: Create a project that uses the remote backend

```bash
mkdir -p ~/lab2.5-state/network && cd ~/lab2.5-state/network
```

Create `main.tf`:

```hcl
# main.tf

terraform {
  required_version = ">= 1.6.0"

  # Remote backend configuration
  backend "s3" {
    bucket         = "lab25-terraform-state-ACCOUNT_ID"  # Replace with your bucket name
    key            = "network/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Create a VPC whose outputs other projects can read
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "lab25-shared-vpc"
    Environment = terraform.workspace  # Uses current workspace name
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet("10.0.0.0/16", 8, count.index + 1)
  map_public_ip_on_launch = true

  tags = {
    Name = "lab25-public-${count.index + 1}"
  }
}

output "vpc_id" {
  description = "VPC ID for other projects to consume"
  value       = aws_vpc.main.id
}

output "subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}
```

> **Important:** Replace `ACCOUNT_ID` in the bucket name with your actual AWS account ID from the bootstrap output.

### Step 6: Initialize with the remote backend

```bash
terraform init
```

Expected output:

```
Initializing the backend...

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.

Initializing provider plugins...
...

Terraform has been successfully initialized!
```

### Step 7: Apply and verify state is remote

```bash
terraform apply -auto-approve

# Verify: no local state file exists
ls terraform.tfstate 2>/dev/null || echo "No local state file (state is in S3)"

# Verify: state is in S3
aws s3 ls s3://lab25-terraform-state-ACCOUNT_ID/network/
```

Expected:

```
No local state file (state is in S3)
2024-01-15 10:30:00       5678 terraform.tfstate
```

---

## Part 4 — State Locking in Action

### Step 8: Observe locking

Open two terminals and try to apply simultaneously:

```bash
# Terminal 1
cd ~/lab2.5-state/network
terraform apply -auto-approve

# Terminal 2 (run immediately while Terminal 1 is still applying)
cd ~/lab2.5-state/network
terraform apply -auto-approve
```

Terminal 2 should show:

```
Acquiring state lock. This may take a few moments...

Error: Error acquiring the state lock

Error message: ConditionalCheckFailedException: The conditional request failed
Lock Info:
  ID:        a1b2c3d4-e5f6-7890-abcd-ef1234567890
  Path:      lab25-terraform-state-123456789012/network/terraform.tfstate
  Operation: OperationTypeApply
  Who:       user@hostname
  Version:   1.6.x
  Created:   2024-01-15 10:35:00 UTC
  Info:

Terraform acquires a state lock to protect the state from being written
by multiple users at the same time.
```

> **Tip:** If a lock gets stuck (e.g., process crashed), you can force-unlock it:
> ```bash
> terraform force-unlock LOCK_ID
> ```
> Use this with extreme caution -- only when you are certain no other operation is running.

---

## Part 5 — Workspaces for Environment Isolation

Workspaces let you maintain multiple state files within the same backend configuration.

### Step 9: Create and switch workspaces

```bash
cd ~/lab2.5-state/network

# List workspaces
terraform workspace list
# Output:
# * default

# Create staging workspace
terraform workspace new staging
# Output: Created and switched to workspace "staging"!

# Create production workspace
terraform workspace new production

# List all workspaces
terraform workspace list
# Output:
#   default
#   production
# * staging

# Switch between workspaces
terraform workspace select staging
```

### Step 10: Apply in each workspace

```bash
# Apply in staging workspace
terraform workspace select staging
terraform apply -auto-approve

# Apply in production workspace
terraform workspace select production
terraform apply -auto-approve

# Each workspace has its own state file in S3:
# s3://bucket/env:/staging/network/terraform.tfstate
# s3://bucket/env:/production/network/terraform.tfstate
```

Verify in S3:

```bash
aws s3 ls s3://lab25-terraform-state-ACCOUNT_ID/ --recursive | grep terraform.tfstate
```

Expected:

```
network/terraform.tfstate                       (default workspace)
env:/staging/network/terraform.tfstate           (staging workspace)
env:/production/network/terraform.tfstate        (production workspace)
```

> **Tip:** Use `terraform.workspace` in your config to customize resources per workspace:
> ```hcl
> tags = {
>   Environment = terraform.workspace
> }
> ```

### Backend Limitations

| Limitation                    | Description                                              |
|-------------------------------|----------------------------------------------------------|
| No partial configuration      | Backend config cannot use variables or locals            |
| Chicken-and-egg               | Backend infrastructure must exist before use             |
| Workspace coupling            | All workspaces share the same backend configuration      |
| No cross-backend references   | Cannot natively reference state in a different backend   |

---

## Part 6 — File Layout Isolation (Recommended for Production)

For stronger isolation, use separate directories per environment, each with its own backend key.

### Step 11: Set up directory-based isolation

```bash
mkdir -p ~/lab2.5-state/environments/{dev,staging,prod}
```

Create a shared module first:

```bash
mkdir -p ~/lab2.5-state/modules/network
```

```hcl
# ~/lab2.5-state/modules/network/main.tf

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  }
}

output "vpc_id" {
  value = aws_vpc.main.id
}
```

Now create environment-specific configs:

```hcl
# ~/lab2.5-state/environments/dev/main.tf

terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket         = "lab25-terraform-state-ACCOUNT_ID"
    key            = "environments/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "network" {
  source      = "../../modules/network"
  environment = "dev"
  vpc_cidr    = "10.0.0.0/16"
}

output "vpc_id" {
  value = module.network.vpc_id
}
```

```hcl
# ~/lab2.5-state/environments/prod/main.tf

terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket         = "lab25-terraform-state-ACCOUNT_ID"
    key            = "environments/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "network" {
  source      = "../../modules/network"
  environment = "prod"
  vpc_cidr    = "10.1.0.0/16"
}

output "vpc_id" {
  value = module.network.vpc_id
}
```

> **Why file layout over workspaces?** File layout provides complete blast radius isolation. A mistake in the dev config cannot accidentally affect prod state. Different environments can use different provider versions or backend configs.

---

## Part 7 — `terraform_remote_state` Data Source

The `terraform_remote_state` data source reads outputs from another Terraform state file. This enables cross-project resource sharing.

### Step 12: Create a project that reads from the network state

```bash
mkdir -p ~/lab2.5-state/app && cd ~/lab2.5-state/app
```

```hcl
# ~/lab2.5-state/app/main.tf

terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket         = "lab25-terraform-state-ACCOUNT_ID"
    key            = "app/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Read outputs from the network project's state
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "lab25-terraform-state-ACCOUNT_ID"
    key    = "network/terraform.tfstate"
    region = "us-east-1"
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Use the VPC ID and subnet IDs from the network project
resource "aws_instance" "app" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  subnet_id     = data.terraform_remote_state.network.outputs.subnet_ids[0]

  tags = {
    Name = "lab25-app-server"
    VPC  = data.terraform_remote_state.network.outputs.vpc_id
  }
}

output "instance_id" {
  value = aws_instance.app.id
}

output "network_vpc_id" {
  description = "VPC ID read from remote state"
  value       = data.terraform_remote_state.network.outputs.vpc_id
}
```

### Step 13: Apply and verify cross-state reference

```bash
cd ~/lab2.5-state/app
terraform init
terraform plan
```

Expected output:

```
data.terraform_remote_state.network: Reading...
data.terraform_remote_state.network: Read complete after 1s

  # aws_instance.app will be created
  + resource "aws_instance" "app" {
      + subnet_id = "subnet-0abc123"  # <-- from the network state!
      ...
    }
```

---

## Part 8 — Importing Existing Resources

### Step 14: Import using `terraform import` command

```bash
cd ~/lab2.5-state && mkdir import-demo && cd import-demo
```

```hcl
# main.tf

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# First, create a resource outside Terraform
# (simulating existing infrastructure)
```

```bash
# Create an S3 bucket outside Terraform
aws s3 mb s3://lab25-import-demo-manual-bucket

# Now write the Terraform config for it
cat >> main.tf <<'EOF'

resource "aws_s3_bucket" "imported" {
  bucket = "lab25-import-demo-manual-bucket"

  tags = {
    Name      = "imported-bucket"
    ManagedBy = "terraform"
  }
}
EOF

terraform init

# Import the existing bucket into Terraform state
terraform import aws_s3_bucket.imported lab25-import-demo-manual-bucket
```

Expected output:

```
aws_s3_bucket.imported: Importing from ID "lab25-import-demo-manual-bucket"...
aws_s3_bucket.imported: Import prepared!
  Prepared aws_s3_bucket for import
aws_s3_bucket.imported: Refreshing state... [id=lab25-import-demo-manual-bucket]

Import successful!

The resources that were imported are shown above. These resources are now in
your Terraform state and will henceforth be managed by Terraform.
```

```bash
# Verify the import: plan should show minimal changes (just tags)
terraform plan
```

### Step 15: Import using `import` blocks (Terraform 1.5+)

The declarative `import` block approach is preferred for repeatable imports:

```hcl
# import-block-demo.tf

# Declare the import
import {
  to = aws_s3_bucket.another_imported
  id = "lab25-import-demo-manual-bucket-2"
}

resource "aws_s3_bucket" "another_imported" {
  bucket = "lab25-import-demo-manual-bucket-2"

  tags = {
    Name      = "another-imported-bucket"
    ManagedBy = "terraform"
  }
}
```

```bash
# Create the second bucket manually first
aws s3 mb s3://lab25-import-demo-manual-bucket-2

# Plan will show the import
terraform plan

# Apply executes the import
terraform apply -auto-approve
```

### Step 16: Generate configuration from imports (Terraform 1.5+)

```bash
# Create another bucket to import
aws s3 mb s3://lab25-import-demo-generated

# Create a file with just the import block
cat > generate-demo.tf <<'EOF'
import {
  to = aws_s3_bucket.generated
  id = "lab25-import-demo-generated"
}
EOF

# Generate the HCL configuration automatically
terraform plan -generate-config-out=generated_resources.tf
```

Expected output:

```
Planning with import... (1 resources to import)

aws_s3_bucket.generated: Preparing import... [id=lab25-import-demo-generated]

Terraform has generated configuration and written it to generated_resources.tf.
```

Review the generated file:

```bash
cat generated_resources.tf
```

The generated file will contain a complete `aws_s3_bucket` resource with all attributes populated from the existing bucket.

> **Tip:** The generated configuration often includes unnecessary attributes. Review and clean it up, keeping only the attributes you want to manage.

---

## Clean Up

```bash
# Clean up import demo
cd ~/lab2.5-state/import-demo
terraform destroy -auto-approve
aws s3 rb s3://lab25-import-demo-generated --force 2>/dev/null

# Clean up app project
cd ~/lab2.5-state/app
terraform destroy -auto-approve

# Clean up network project (all workspaces)
cd ~/lab2.5-state/network
terraform workspace select production
terraform destroy -auto-approve
terraform workspace select staging
terraform destroy -auto-approve
terraform workspace select default
terraform destroy -auto-approve

# Clean up bootstrap (remove prevent_destroy first, then destroy)
cd ~/lab2.5-state/bootstrap
# Edit bootstrap.tf: change prevent_destroy to false
terraform destroy -auto-approve
```

---

## Summary

| Concept                  | What You Learned                                                    |
|--------------------------|---------------------------------------------------------------------|
| State file structure     | JSON mapping of config to real resources, contains sensitive data   |
| S3 backend               | Remote state with encryption, versioning, and team access           |
| DynamoDB locking         | Prevents concurrent state modifications                             |
| Workspaces               | Multiple state files per backend config, good for simple setups     |
| File layout isolation    | Separate directories per environment for production-grade isolation |
| terraform_remote_state   | Read outputs from another project's state file                      |
| terraform import         | Bring existing resources under Terraform management                 |
| import blocks            | Declarative, repeatable import (Terraform 1.5+)                     |
| generate-config-out      | Auto-generate HCL from existing resources                           |

> **Key takeaway:** State management is the most operationally critical aspect of Terraform. Use remote backends from day one, always enable locking and encryption, prefer file layout isolation for production environments, and use `terraform_remote_state` or data sources (not hardcoded values) to share information between projects.
