# Hands-On 3.1 --- Team Workflows for Terraform

**File:** `.github/workflows/terraform.yml`, `.gitignore`, `main.tf`

---

## Concept

When a single engineer writes Terraform, the code lives on a laptop. When a **team** writes Terraform, the code must live in version control, follow conventions, pass reviews, and flow through a pipeline before it touches real infrastructure.

```
 Developer A            Developer B
     |                       |
     v                       v
 feature/vpc             feature/rds
     |                       |
     +----> Pull Request <---+
                |
                v
        Code Review + Plan
                |
                v
          Merge to main
                |
                v
       CI/CD  terraform apply
                |
                v
         AWS  (Production)
```

This lab covers the full journey: branching strategy, coding guidelines, the plan/apply workflow, and a production-grade CI/CD pipeline with GitHub Actions.

---

## 1. Version Control Strategy for IaC

### Branching Model

| Branch | Purpose | Who merges | Terraform action |
|--------|---------|------------|------------------|
| `main` | Production truth | Lead / CI | `apply` |
| `staging` | Pre-prod validation | Any approved PR | `apply` to staging |
| `feature/*` | New infra work | Developer | `plan` only |
| `hotfix/*` | Emergency fixes | Lead | fast-track `apply` |

```
main ──────●──────────●──────────●───────
            \        / \        /
   feature/vpc ●──●    feature/rds ●──●
```

> **Tip:** Never run `terraform apply` from a feature branch against production. Always merge first, then let CI apply.

### Commit Message Convention

```
<type>(<scope>): <description>

feat(vpc): add private subnets in us-east-1a and 1b
fix(sg): allow HTTPS egress to 0.0.0.0/0
refactor(modules): extract ec2 into reusable module
docs(readme): add architecture diagram
```

---

## 2. Coding Guidelines

### Naming Conventions

```
Rule                    Good                         Bad
----                    ----                         ---
snake_case everywhere   web_server_sg                webServerSg
Descriptive names       private_subnet_a             subnet1
Prefix by project       acme_prod_vpc                vpc
Boolean vars            enable_monitoring            monitoring
```

### Standard File Structure

Every Terraform project should follow this layout:

```
project/
  providers.tf      # Provider blocks and required_providers
  variables.tf      # All input variable declarations
  main.tf           # Resource definitions (the "what")
  outputs.tf        # Output values
  locals.tf         # Computed local values
  data.tf           # Data source lookups
  terraform.tfvars  # Variable values (NOT committed for secrets)
  versions.tf       # Terraform version constraints
```

### providers.tf

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "acme-terraform-state"
    key            = "prod/network/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Project     = var.project_name
      Environment = var.environment
    }
  }
}
```

### variables.tf

```hcl
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project identifier used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
```

### outputs.tf

```hcl
output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}
```

---

## 3. The .gitignore File

```gitignore
# .gitignore for Terraform projects

# Local .terraform directories
**/.terraform/*

# .tfstate files (state belongs in remote backend)
*.tfstate
*.tfstate.*

# Crash log files
crash.log
crash.*.log

# Variable files that may contain secrets
*.tfvars
*.tfvars.json

# Override files
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# CLI configuration files
.terraformrc
terraform.rc

# Lock file should be committed
# Do NOT ignore: .terraform.lock.hcl

# OS files
.DS_Store
Thumbs.db

# IDE
.idea/
.vscode/
*.swp
*.swo
```

> **Important:** Always commit `.terraform.lock.hcl`. This file pins the exact provider versions your team uses. Ignoring it causes "works on my machine" problems.

---

## 4. Plan/Apply Workflow

The golden rule: **Plan in staging, review the plan, then apply to prod.**

```
Developer writes code
        |
        v
terraform fmt -check        (formatting)
        |
        v
terraform validate           (syntax + type check)
        |
        v
terraform plan -out=plan.bin (preview changes)
        |
        v
Post plan to Pull Request    (team reviews)
        |
        v
Merge to main                (approval gate)
        |
        v
terraform apply plan.bin     (execute reviewed plan)
        |
        v
State updated in S3          (remote backend)
```

### Plan Output Example

```bash
$ terraform plan -out=tfplan

Terraform will perform the following actions:

  # aws_instance.web will be created
  + resource "aws_instance" "web" {
      + ami                    = "ami-0c55b159cbfafe1f0"
      + instance_type          = "t3.micro"
      + tags                   = {
          + "Name" = "web-server"
        }
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

---

## 5. CI/CD Pipeline --- GitHub Actions

### Full Code: `.github/workflows/terraform.yml`

```yaml
name: "Terraform CI/CD"

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read
  pull-requests: write
  id-token: write          # For OIDC authentication with AWS

env:
  TF_VERSION: "1.7.0"
  AWS_REGION: "us-east-1"

jobs:
  # ──────────────────────────────────────────────
  # Stage 1: Validate and Plan
  # ──────────────────────────────────────────────
  terraform-plan:
    name: "Plan"
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}
          terraform_wrapper: false

      - name: Configure AWS Credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-terraform
          aws-region: ${{ env.AWS_REGION }}

      - name: Terraform Format Check
        id: fmt
        run: terraform fmt -check -recursive
        continue-on-error: true

      - name: Terraform Init
        id: init
        run: terraform init -input=false

      - name: Terraform Validate
        id: validate
        run: terraform validate -no-color

      - name: Terraform Plan
        id: plan
        run: |
          terraform plan -no-color -input=false -out=tfplan \
            2>&1 | tee plan_output.txt
        continue-on-error: true

      - name: Post Plan to PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const plan = fs.readFileSync('plan_output.txt', 'utf8');
            const maxLen = 60000;
            const truncated = plan.length > maxLen
              ? plan.substring(0, maxLen) + '\n... (truncated)'
              : plan;

            const body = `#### Terraform Format: \`${{ steps.fmt.outcome }}\`
            #### Terraform Init: \`${{ steps.init.outcome }}\`
            #### Terraform Validate: \`${{ steps.validate.outcome }}\`
            #### Terraform Plan: \`${{ steps.plan.outcome }}\`

            <details><summary>Show Plan</summary>

            \`\`\`
            ${truncated}
            \`\`\`

            </details>

            *Pushed by: @${{ github.actor }}*`;

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: body
            });

      - name: Plan Status
        if: steps.plan.outcome == 'failure'
        run: exit 1

      - name: Upload Plan Artifact
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: tfplan

  # ──────────────────────────────────────────────
  # Stage 2: Apply (only on main branch push)
  # ──────────────────────────────────────────────
  terraform-apply:
    name: "Apply"
    runs-on: ubuntu-latest
    needs: terraform-plan
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment: production
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Configure AWS Credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-terraform
          aws-region: ${{ env.AWS_REGION }}

      - name: Terraform Init
        run: terraform init -input=false

      - name: Download Plan Artifact
        uses: actions/download-artifact@v4
        with:
          name: tfplan

      - name: Terraform Apply
        run: terraform apply -auto-approve -input=false tfplan
```

---

## 6. Automated Testing --- Conceptual Overview

```
+-------------------+    +-------------------+    +-------------------+
|   Static Tests    |    |  Integration Tests |   |   End-to-End      |
|                   |    |                    |   |                   |
| terraform fmt     |    | Terratest (Go)     |   | Deploy full stack |
| terraform validate|    | Kitchen-Terraform  |   | Run smoke tests   |
| tflint            |    | pytest + boto3     |   | Destroy stack     |
| tfsec / checkov   |    |                    |   |                   |
+-------------------+    +-------------------+    +-------------------+
     Seconds                  Minutes                  10+ Minutes
     Every commit             Every PR                 Nightly/Release
```

| Tool | Type | What it checks |
|------|------|----------------|
| `terraform fmt` | Formatting | Consistent code style |
| `terraform validate` | Syntax | Valid HCL, correct types |
| `tflint` | Linter | Deprecated syntax, best practices |
| `tfsec` | Security | Misconfigurations (open SGs, unencrypted disks) |
| `checkov` | Compliance | CIS benchmarks, custom policies |
| `Terratest` | Integration | Actually deploys and tests real resources |

---

## 7. Hands-On: Simulate a Team Workflow

### Step 1: Initialize a Git Repository

```bash
mkdir -p ~/terraform-team-lab && cd ~/terraform-team-lab

git init
git branch -m main
```

Expected output:
```
Initialized empty Git repository in /home/user/terraform-team-lab/.git/
```

### Step 2: Create the Project Structure

```bash
# Create standard files
touch providers.tf variables.tf main.tf outputs.tf
```

**providers.tf:**
```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

**variables.tf:**
```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
```

**main.tf:**
```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
```

**outputs.tf:**
```hcl
output "vpc_id" {
  description = "The VPC ID"
  value       = aws_vpc.main.id
}
```

### Step 3: Create .gitignore and Commit

```bash
# Write the .gitignore (use the one from Section 3 above)
cat > .gitignore << 'GITIGNORE'
**/.terraform/*
*.tfstate
*.tfstate.*
crash.log
crash.*.log
*.tfvars
*.tfvars.json
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc
.DS_Store
.idea/
.vscode/
GITIGNORE

# Initial commit
git add .
git commit -m "feat(init): bootstrap terraform project structure"
```

Expected output:
```
[main (root-commit) a1b2c3d] feat(init): bootstrap terraform project structure
 5 files changed, 42 insertions(+)
 create mode 100644 .gitignore
 create mode 100644 main.tf
 create mode 100644 outputs.tf
 create mode 100644 providers.tf
 create mode 100644 variables.tf
```

### Step 4: Create a Feature Branch

```bash
git checkout -b feature/add-subnets
```

### Step 5: Add Subnet Resources

Append to **main.tf:**

```hcl
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.environment}-public-subnet"
    Environment = var.environment
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name        = "${var.environment}-private-subnet"
    Environment = var.environment
  }
}
```

### Step 6: Validate Locally

```bash
terraform init
terraform fmt -check
terraform validate
```

Expected output:
```
Terraform has been successfully initialized!
Success! The configuration is valid.
```

### Step 7: Commit and Simulate PR

```bash
git add main.tf
git commit -m "feat(network): add public and private subnets"

# Show what the PR diff would look like
git log --oneline main..feature/add-subnets
git diff main..feature/add-subnets
```

Expected output:
```
abc1234 feat(network): add public and private subnets

diff --git a/main.tf b/main.tf
...
+resource "aws_subnet" "public" {
...
```

### Step 8: Merge (Simulating Approved PR)

```bash
git checkout main
git merge --no-ff feature/add-subnets -m "Merge feature/add-subnets (#1)"
git log --oneline --graph
```

Expected output:
```
*   def5678 Merge feature/add-subnets (#1)
|\
| * abc1234 feat(network): add public and private subnets
|/
* a1b2c3d feat(init): bootstrap terraform project structure
```

### Step 9: Clean Up Branch

```bash
git branch -d feature/add-subnets
git branch -a
```

---

## 8. Summary

| Practice | Why it matters |
|----------|---------------|
| Git branching | Isolates changes, enables review |
| Standard file layout | Team knows where to find things |
| `terraform fmt` | Consistent style, no bikeshedding |
| Plan-then-apply | No surprises in production |
| CI/CD pipeline | Automated gates prevent mistakes |
| .gitignore | Secrets and state never leak to git |
| Commit conventions | Clean history, easy rollbacks |

> **Key takeaway:** Terraform is code. Treat it with the same rigor you apply to application code --- version control, code review, automated testing, and CI/CD pipelines.
