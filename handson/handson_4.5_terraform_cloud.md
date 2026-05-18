# Hands-On 4.5 — Terraform Cloud

**File:** `~/lab4.5-tfc/`

---

## Concept

Terraform Cloud (TFC) is HashiCorp's managed service that adds collaboration, governance, and automation to Terraform workflows. It eliminates the need to manage your own state backend, CI/CD pipelines, and access controls. This lab walks through setting up TFC from scratch: workspaces, remote execution, VCS integration, and the private module registry.

### Terraform Cloud Architecture

```
  Developer                    Terraform Cloud                    AWS
  +---------+                 +--------------------+            +-------+
  |         |  terraform      |                    |  API calls |       |
  |  CLI /  |  plan/apply     |  +----------+      |            |       |
  |  VCS    |---------------->|  | Workspace|      |----------->|  EC2  |
  |  push   |                 |  |  - State |      |            |  S3   |
  |         |<----------------|  |  - Vars  |      |<-----------|  VPC  |
  |         |  streamed       |  |  - Runs  |      |            |       |
  |         |  output         |  +----------+      |            +-------+
  +---------+                 |                    |
                              |  +----------+      |
                              |  | Registry |      |
                              |  | - Modules|      |
                              |  | - Policies|     |
                              |  +----------+      |
                              +--------------------+
```

### TFC Free Tier Features

| Feature | Free Tier | Plus | Business |
|---------|-----------|------|----------|
| Workspaces | Up to 500 | Unlimited | Unlimited |
| State management | Yes | Yes | Yes |
| Remote execution | Yes | Yes | Yes |
| VCS integration | Yes | Yes | Yes |
| Private registry | Yes | Yes | Yes |
| Team management | 1 team | Multiple | SSO + RBAC |
| Policy as code | No | Sentinel | Sentinel + OPA |
| Audit logging | No | No | Yes |
| Self-hosted agents | No | No | Yes |

---

## Part 1 — Sign Up and Initial Setup

### Step 1: Create a Terraform Cloud account

```
1. Go to https://app.terraform.io/signup/account
2. Create account with email or GitHub SSO
3. Create an organization (e.g., "my-training-org")
4. Note your organization name -- you will need it
```

### Step 2: Create an API token

```bash
# Login via CLI -- this opens a browser to generate a token
terraform login

# Expected:
# Terraform will request an API token for app.terraform.io using your browser.
# Token for app.terraform.io: <paste token here>
# Success! Terraform has obtained and saved an API token.

# The token is stored in:
cat ~/.terraform.d/credentials.tfrc.json
```

---

## Part 2 — Workspaces

### CLI-Driven Workspace

The CLI-driven workflow lets you run `terraform plan` and `terraform apply` from your local machine, but execution happens remotely in TFC.

### Step 3: Create a workspace via the cloud block

```bash
mkdir -p ~/lab4.5-tfc/cli-workspace && cd ~/lab4.5-tfc/cli-workspace
```

```hcl
# main.tf

terraform {
  required_version = ">= 1.6.0"

  cloud {
    organization = "my-training-org"    # Replace with your org

    workspaces {
      name = "lab45-cli-demo"
    }
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

variable "environment" {
  type    = string
  default = "dev"
}

resource "aws_s3_bucket" "demo" {
  bucket_prefix = "tfc-demo-${var.environment}-"

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform-cloud"
  }
}

output "bucket_name" {
  value = aws_s3_bucket.demo.id
}
```

```bash
# Initialize -- creates the workspace in TFC if it does not exist
terraform init

# Expected:
# Initializing Terraform Cloud...
# Terraform Cloud has been successfully initialized!
```

### Step 4: Configure workspace variables in TFC

Go to TFC UI: Workspaces > lab45-cli-demo > Variables

```
  Workspace Variables:
  +------------------+------------------+-------------+-----------+
  | Key              | Value            | Category    | Sensitive |
  +------------------+------------------+-------------+-----------+
  | environment      | dev              | Terraform   | No        |
  | AWS_ACCESS_KEY_ID| AKIA...          | Environment | Yes       |
  | AWS_SECRET_ACCESS_KEY| wJal...      | Environment | Yes       |
  | AWS_DEFAULT_REGION| us-east-1       | Environment | No        |
  +------------------+------------------+-------------+-----------+
```

> **Tip:** For production, use dynamic credentials (OIDC) instead of static AWS keys. TFC supports AWS OIDC federation natively.

### Step 5: Run a remote plan

```bash
terraform plan
```

Expected output:
```
Running plan in Terraform Cloud. Output will stream here.
Waiting for the plan to start...

Terraform v1.8.0
on linux_amd64

Terraform used the selected providers to generate the following
execution plan.

Plan: 1 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + bucket_name = (known after apply)
```

```bash
terraform apply
```

Expected:
```
Do you want to perform these actions in workspace "lab45-cli-demo"?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:
bucket_name = "tfc-demo-dev-20260518123456"
```

---

## Part 3 — Terraform Cloud Projects

Projects organize workspaces into logical groups.

```
  Organization: my-training-org
  |
  +-- Project: Networking
  |   +-- Workspace: networking-dev
  |   +-- Workspace: networking-staging
  |   +-- Workspace: networking-prod
  |
  +-- Project: Applications
  |   +-- Workspace: webapp-dev
  |   +-- Workspace: webapp-staging
  |   +-- Workspace: webapp-prod
  |
  +-- Project: Data
      +-- Workspace: database-dev
      +-- Workspace: database-prod
```

### Create projects via CLI

```bash
# Using the TFC API
curl -s \
  --header "Authorization: Bearer $TFC_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --request POST \
  --data '{
    "data": {
      "type": "projects",
      "attributes": {
        "name": "Networking"
      }
    }
  }' \
  https://app.terraform.io/api/v2/organizations/my-training-org/projects
```

---

## Part 4 — Cloud Credentials (Dynamic Credentials)

### OIDC-based AWS Authentication (Recommended)

```
  TFC Workspace              AWS IAM
  +------------------+       +------------------+
  |  Run starts      |       |  OIDC Provider   |
  |  TFC generates   | JWT   |  - Issuer: TFC   |
  |  OIDC token      |------>|  - Audience: aws  |
  |                  |       |  - Trust: org/ws  |
  |  Assumes role    |<------|  - Role: tf-role  |
  |  Gets temp creds |       |                  |
  +------------------+       +------------------+
```

```hcl
# Configure in the workspace settings or via Terraform:

# In TFC workspace variables:
# TFC_AWS_PROVIDER_AUTH = true
# TFC_AWS_RUN_ROLE_ARN = arn:aws:iam::ACCOUNT:role/tfc-role

# AWS IAM trust policy for the role:
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/app.terraform.io"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "app.terraform.io:aud": "aws.workload.identity"
        },
        "StringLike": {
          "app.terraform.io:sub": "organization:my-training-org:project:*:workspace:*:run_phase:*"
        }
      }
    }
  ]
}
```

---

## Part 5 — Private Module Registry

### Step 6: Publish a module to TFC registry

Requirements for auto-discovery:
- Repository name: `terraform-<PROVIDER>-<NAME>` (e.g., `terraform-aws-vpc`)
- Must have a tagged release (semver)
- Must contain `main.tf`, `variables.tf`, `outputs.tf` at root or in a `modules/` subdir

### Step 6a: Create module repository

```bash
mkdir -p ~/lab4.5-tfc/terraform-aws-tags && cd ~/lab4.5-tfc/terraform-aws-tags
git init
```

```hcl
# main.tf

locals {
  standard_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
  }
  all_tags = merge(local.standard_tags, var.extra_tags)
}
```

```hcl
# variables.tf

variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "owner" {
  description = "Resource owner"
  type        = string
  default     = "platform-team"
}

variable "extra_tags" {
  description = "Additional tags to merge"
  type        = map(string)
  default     = {}
}
```

```hcl
# outputs.tf

output "tags" {
  description = "All tags to apply to resources"
  value       = local.all_tags
}
```

```bash
git add .
git commit -m "Initial tags module"
git tag -a v1.0.0 -m "v1.0.0"

# Push to GitHub (must be connected to TFC)
git remote add origin https://github.com/myorg/terraform-aws-tags.git
git push -u origin main --tags
```

### Step 6b: Publish in TFC

```
1. Go to TFC > Registry > Modules > Publish
2. Connect to VCS (GitHub)
3. Select repository: terraform-aws-tags
4. TFC auto-detects the module and imports tagged versions
```

### Step 6c: Consume the private module

```hcl
# In any workspace:

module "tags" {
  source  = "app.terraform.io/my-training-org/tags/aws"
  version = "~> 1.0"

  project     = "myapp"
  environment = "dev"
  owner       = "web-team"
}

resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"
  tags          = module.tags.tags
}
```

---

## Part 6 — VCS Integration for CI/CD

### VCS-Driven Workflow

```
  Developer          GitHub              Terraform Cloud
  +--------+        +--------+          +----------------+
  | push   |------->| PR     |--------->| Speculative    |
  | branch |        | opened |  webhook | Plan           |
  +--------+        |        |          | (comment on PR)|
                    |        |          +----------------+
                    | PR     |
  +--------+        | merged |--------->+----------------+
  | approve|------->| to     |  webhook | Apply          |
  | merge  |        | main   |          | (auto or manual|
  +--------+        +--------+          +----------------+
```

### Configure VCS connection

```
1. TFC > Settings > VCS Providers > Add VCS Provider
2. Select GitHub.com (or GitHub Enterprise)
3. Follow OAuth flow to authorize
4. TFC can now watch repositories
```

### Create a VCS-backed workspace

```
1. TFC > Workspaces > New Workspace
2. Choose "Version control workflow"
3. Select the VCS provider (GitHub)
4. Choose repository
5. Configure:
   - Working Directory: environments/dev/
   - VCS branch: main
   - Auto-apply: disabled (require manual confirmation)
```

### Workspace settings for production

```
  Workspace: webapp-prod
  +----------------------------------------+
  | General Settings                       |
  |   Execution Mode: Remote               |
  |   Apply Method: Manual (require approval)|
  |   Terraform Version: ~> 1.8.0          |
  +----------------------------------------+
  | VCS Settings                           |
  |   Repository: myorg/infrastructure     |
  |   Branch: main                         |
  |   Working Directory: environments/prod |
  |   Trigger: Only on changes to this path|
  +----------------------------------------+
  | Run Triggers                           |
  |   Source: networking-prod workspace     |
  |   (auto-plan when networking changes)  |
  +----------------------------------------+
```

---

## Part 7 — Remote Execution Deep Dive

### Speculative Plans

Speculative plans run on pull requests and do NOT lock the workspace.

```bash
# Trigger from CLI (local files, remote execution)
terraform plan

# The plan runs in TFC but uses your local code
# Output is streamed back to your terminal
```

### Run Triggers (Workspace Chaining)

```
  networking-prod        app-prod
  +-----------+         +-----------+
  | VPC, SG   | apply   | EC2, ALB  |
  | changes   |-------->| auto-plan |
  +-----------+  trigger +-----------+
```

Configure in TFC:
```
app-prod > Settings > Run Triggers > Add Source Workspace > networking-prod
```

---

## Part 8 — Terraform Enterprise Overview

| Feature | Terraform Cloud | Terraform Enterprise |
|---------|----------------|---------------------|
| Hosting | SaaS | Self-hosted (your VPC) |
| Data residency | HashiCorp managed | Your control |
| SSO | Business tier | Included |
| Audit logs | Business tier | Included |
| Custom agents | Business tier | Included |
| Air-gapped | No | Yes |
| Sentinel policies | Plus+ | Included |
| Cost estimation | Yes | Yes |
| Pricing | Per-resource | License-based |

### When to Choose Enterprise

- Regulatory requirements for data residency
- Air-gapped or restricted network environments
- Need for custom concurrency controls
- Organization requires on-premises deployment

---

## Hands-On Cleanup

```bash
# Destroy resources in the workspace
cd ~/lab4.5-tfc/cli-workspace
terraform destroy -auto-approve

# Delete workspace via API (optional)
curl -s \
  --header "Authorization: Bearer $TFC_TOKEN" \
  --request DELETE \
  https://app.terraform.io/api/v2/organizations/my-training-org/workspaces/lab45-cli-demo
```

---

## Summary

| Feature | What It Does | How to Use |
|---------|-------------|------------|
| Workspaces | Isolate state and variables | `cloud {}` block, or TFC UI |
| Projects | Group workspaces logically | TFC UI or API |
| Cloud Credentials | OIDC-based dynamic auth | Workspace variables |
| Private Registry | Host internal modules | Publish from VCS repo |
| Remote Execution | Run plan/apply in TFC | CLI or VCS trigger |
| VCS Integration | Auto-plan on PR, apply on merge | Connect GitHub in TFC |
| Run Triggers | Chain workspace runs | Configure source workspaces |
| Enterprise | Self-hosted TFC | On-prem installation |
