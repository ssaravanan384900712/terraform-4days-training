# Hands-On 3.8 --- Collaborative Infrastructure

**File:** `terragrunt.hcl`, `.gitignore`, `Jenkinsfile`, `test/infra_test.go`

---

## Concept

Real-world Terraform runs across teams, environments, and pipelines. This lab covers the full collaboration stack: Git workflow, secret protection, remote state sharing, Terragrunt for DRY configs, CI pipelines, integration testing, workspaces, and debugging techniques.

```
Developer Laptop                  CI/CD Pipeline               AWS
+----------------+          +----------------------+     +-------------+
| Write .tf code |  push    | GitHub Actions /      |     |  dev        |
| git commit     | -------> | Jenkins                |     |  staging    |
| git push       |          | terraform init         |     |  prod       |
+----------------+          | terraform plan         |     +------+------+
       |                    | (review / approve)     |            |
       |                    | terraform apply        | ---------->|
       |                    +----------------------+     State in S3
       |
       +--- Secrets in AWS Secrets Manager / SSM
            (never in git)
```

---

## 1. Git 101 for Terraform

### Essential Git Commands

```bash
# Initialize
git init
git remote add origin git@github.com:acme/infra.git

# Daily workflow
git checkout -b feature/add-rds
# ... edit files ...
git add main.tf variables.tf
git commit -m "feat(rds): add PostgreSQL RDS instance"
git push -u origin feature/add-rds

# Create PR on GitHub, get review, merge
git checkout main
git pull origin main
git branch -d feature/add-rds
```

### Branching Strategy for IaC

```
main (production)
  |
  +--- feature/add-vpc        (short-lived, PR to main)
  |
  +--- feature/update-rds     (short-lived, PR to main)
  |
  +--- hotfix/fix-sg-rules    (urgent, fast-track PR)
```

> **Tip:** Keep branches short-lived (1-3 days). Long-lived IaC branches cause painful merge conflicts because state can diverge.

### .gitignore for Terraform

```gitignore
# Terraform
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

# Keep the lock file
!.terraform.lock.hcl

# Secrets
*.pem
*.key
.env
secrets/

# Terragrunt
.terragrunt-cache/

# OS
.DS_Store
Thumbs.db
```

---

## 2. Protecting Secrets

### What NEVER Goes in Git

```
NEVER COMMIT:
  - AWS access keys / secret keys
  - Database passwords
  - API tokens
  - Private SSH keys
  - *.tfvars with secrets
  - .env files
```

### Strategy 1: AWS Secrets Manager

```hcl
# Store secret externally, read via data source
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "prod/database/password"
}

resource "aws_db_instance" "main" {
  engine         = "postgres"
  instance_class = "db.t3.micro"
  username       = "admin"
  password       = data.aws_secretsmanager_secret_version.db_password.secret_string

  # Never show password in plan output
  lifecycle {
    ignore_changes = [password]
  }
}
```

### Strategy 2: AWS SSM Parameter Store

```hcl
data "aws_ssm_parameter" "db_password" {
  name            = "/prod/database/password"
  with_decryption = true
}

resource "aws_db_instance" "main" {
  # ...
  password = data.aws_ssm_parameter.db_password.value
}
```

### Strategy 3: Sensitive Variables

```hcl
variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

# Pass via environment variable (never in .tfvars committed to git)
# TF_VAR_db_password=supersecret terraform apply
```

### Strategy 4: .tfvars with .gitignore

```bash
# Create a secrets file (NOT committed)
cat > secrets.tfvars << 'EOF'
db_password = "supersecret123!"
api_key     = "sk-abc123def456"
EOF

# Apply with secrets file
terraform apply -var-file=secrets.tfvars

# .gitignore already excludes *.tfvars
```

---

## 3. Remote State Sharing

When multiple Terraform projects need each other's data, use `terraform_remote_state`:

```
Project A: Network           Project B: Compute
+-----------------+          +-----------------+
| VPC, subnets    |          | EC2, ASG        |
| outputs:        |          | needs:          |
|   vpc_id        |  ------> |   vpc_id        |
|   subnet_ids    |  state   |   subnet_ids    |
+-----------------+  lookup  +-----------------+
     |                            |
     v                            v
S3: network/tfstate          S3: compute/tfstate
```

### Project A: Network (writes outputs)

```hcl
# network/outputs.tf
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
```

### Project B: Compute (reads remote state)

```hcl
# compute/data.tf
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "mycompany-terraform-state"
    key    = "prod/network/terraform.tfstate"
    region = "us-east-1"
  }
}

# compute/main.tf
resource "aws_instance" "web" {
  ami       = data.aws_ami.latest.id
  subnet_id = data.terraform_remote_state.network.outputs.public_subnet_ids[0]
  # ...
}
```

> **Tip:** Prefer data sources over remote state when possible. `data "aws_vpc"` queries live AWS, while `terraform_remote_state` reads from the last apply of another project (which could be stale).

---

## 4. Terragrunt --- DRY Terraform Configurations

Terragrunt is a thin wrapper around Terraform that provides extra tools for keeping configurations DRY, working with multiple modules, and managing remote state.

### Why Terragrunt?

```
Without Terragrunt                With Terragrunt
─────────────────                 ───────────────
environments/                     environments/
  dev/                              terragrunt.hcl (root)
    backend.tf (copy)               dev/
    provider.tf (copy)                terragrunt.hcl (3 lines)
    variables.tf (copy)             staging/
    main.tf (copy)                    terragrunt.hcl (3 lines)
  staging/                          prod/
    backend.tf (copy)                 terragrunt.hcl (3 lines)
    provider.tf (copy)            modules/
    variables.tf (copy)             vpc/main.tf
    main.tf (copy)                  ec2/main.tf
  prod/
    backend.tf (copy)
    provider.tf (copy)
    variables.tf (copy)
    main.tf (copy)
```

### Install Terragrunt

```bash
# Linux
curl -L https://github.com/gruntwork-io/terragrunt/releases/latest/download/terragrunt_linux_amd64 \
  -o /usr/local/bin/terragrunt && chmod +x /usr/local/bin/terragrunt

# macOS
brew install terragrunt

# Verify
terragrunt --version
```

### Project Structure

```
infrastructure/
├── terragrunt.hcl                    # Root config (backend, provider)
├── environments/
│   ├── dev/
│   │   ├── terragrunt.hcl           # Env-level overrides
│   │   ├── vpc/
│   │   │   └── terragrunt.hcl       # Module config
│   │   └── ec2/
│   │       └── terragrunt.hcl       # Module config
│   ├── staging/
│   │   ├── terragrunt.hcl
│   │   ├── vpc/
│   │   │   └── terragrunt.hcl
│   │   └── ec2/
│   │       └── terragrunt.hcl
│   └── prod/
│       ├── terragrunt.hcl
│       ├── vpc/
│       │   └── terragrunt.hcl
│       └── ec2/
│           └── terragrunt.hcl
└── modules/
    ├── vpc/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── ec2/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### Root terragrunt.hcl

```hcl
# infrastructure/terragrunt.hcl

# Auto-generate backend configuration
remote_state {
  backend = "s3"

  config = {
    bucket         = "mycompany-terraform-state"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# Auto-generate provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    provider "aws" {
      region = "us-east-1"

      default_tags {
        tags = {
          ManagedBy   = "terraform"
          Environment = "${basename(get_terragrunt_dir())}"
        }
      }
    }
  EOF
}
```

### Environment-Level terragrunt.hcl

```hcl
# infrastructure/environments/dev/terragrunt.hcl

# Include the root config
include "root" {
  path = find_in_parent_folders()
}

# Common inputs for all modules in dev
inputs = {
  environment   = "dev"
  instance_type = "t3.micro"
}
```

### Module-Level terragrunt.hcl (VPC)

```hcl
# infrastructure/environments/dev/vpc/terragrunt.hcl

include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path = "${get_terragrunt_dir()}/../terragrunt.hcl"
}

terraform {
  source = "${get_repo_root()}/modules/vpc"
}

inputs = {
  vpc_cidr = "10.0.0.0/16"
  azs      = ["us-east-1a", "us-east-1b"]
}
```

### Module-Level terragrunt.hcl (EC2 with dependency)

```hcl
# infrastructure/environments/dev/ec2/terragrunt.hcl

include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path = "${get_terragrunt_dir()}/../terragrunt.hcl"
}

terraform {
  source = "${get_repo_root()}/modules/ec2"
}

# Declare dependency on VPC
dependency "vpc" {
  config_path = "../vpc"

  # Mock outputs for plan when VPC hasn't been applied yet
  mock_outputs = {
    vpc_id            = "vpc-mock-12345"
    public_subnet_ids = ["subnet-mock-1", "subnet-mock-2"]
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.public_subnet_ids
  server_count = 2
}
```

### Terragrunt Commands

```bash
# Run in a single module
cd environments/dev/vpc
terragrunt plan
terragrunt apply

# Run across ALL modules in an environment
cd environments/dev
terragrunt run-all plan
terragrunt run-all apply

# Destroy in reverse dependency order
terragrunt run-all destroy

# Show dependency graph
terragrunt graph-dependencies
```

Expected `run-all` output:
```
Group 1:
- Module: environments/dev/vpc

Group 2: (depends on Group 1)
- Module: environments/dev/ec2

Are you sure you want to run 'terragrunt apply' in each folder? (y/n)
```

---

## 5. CI Pipeline

### GitHub Actions

```yaml
# .github/workflows/terraform.yml
name: "Terraform"

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  terraform:
    name: "Terraform Plan & Apply"
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.7.0"

      - name: Configure AWS (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1

      - name: Terraform Init
        run: terraform init

      - name: Terraform Format
        run: terraform fmt -check -recursive

      - name: Terraform Validate
        run: terraform validate

      - name: tfsec Security Scan
        uses: aquasecurity/tfsec-action@v1.0.3
        with:
          soft_fail: false

      - name: Terraform Plan
        if: github.event_name == 'pull_request'
        run: terraform plan -no-color -input=false

      - name: Terraform Apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -auto-approve -input=false
```

### Jenkins Pipeline

```groovy
// Jenkinsfile
pipeline {
    agent any

    environment {
        TF_VERSION = '1.7.0'
        AWS_REGION = 'us-east-1'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Terraform Init') {
            steps {
                withAWS(role: 'TerraformDeployRole', roleAccount: '123456789012') {
                    sh 'terraform init -input=false'
                }
            }
        }

        stage('Terraform Validate') {
            steps {
                sh 'terraform fmt -check'
                sh 'terraform validate'
            }
        }

        stage('Security Scan') {
            steps {
                sh 'tfsec . --minimum-severity HIGH'
            }
        }

        stage('Terraform Plan') {
            steps {
                withAWS(role: 'TerraformDeployRole', roleAccount: '123456789012') {
                    sh 'terraform plan -out=tfplan -input=false'
                }
            }
        }

        stage('Approval') {
            when {
                branch 'main'
            }
            steps {
                input message: 'Apply this plan?', ok: 'Apply'
            }
        }

        stage('Terraform Apply') {
            when {
                branch 'main'
            }
            steps {
                withAWS(role: 'TerraformDeployRole', roleAccount: '123456789012') {
                    sh 'terraform apply -auto-approve tfplan'
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
    }
}
```

---

## 6. Integration Testing with Terratest

### Setup

```bash
mkdir -p test
cd test
go mod init github.com/acme/infra-test
go get github.com/gruntwork-io/terratest/modules/terraform
go get github.com/stretchr/testify/assert
```

### Test File

```go
// test/vpc_test.go
package test

import (
    "testing"

    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestVPCModule(t *testing.T) {
    t.Parallel()

    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        // Path to the Terraform code to test
        TerraformDir: "../modules/vpc",

        // Variables to pass
        Vars: map[string]interface{}{
            "vpc_cidr":    "10.99.0.0/16",
            "environment": "test",
            "azs":         []string{"us-east-1a", "us-east-1b"},
        },

        // Disable color in output
        NoColor: true,
    })

    // Destroy everything at the end of the test
    defer terraform.Destroy(t, terraformOptions)

    // Deploy the infrastructure
    terraform.InitAndApply(t, terraformOptions)

    // Validate outputs
    vpcID := terraform.Output(t, terraformOptions, "vpc_id")
    assert.NotEmpty(t, vpcID)
    assert.Contains(t, vpcID, "vpc-")

    publicSubnets := terraform.OutputList(t, terraformOptions, "public_subnet_ids")
    assert.Equal(t, 2, len(publicSubnets))

    vpcCIDR := terraform.Output(t, terraformOptions, "vpc_cidr")
    assert.Equal(t, "10.99.0.0/16", vpcCIDR)
}

func TestVPCModuleWithDefaults(t *testing.T) {
    t.Parallel()

    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../modules/vpc",
        NoColor:      true,
    })

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    vpcID := terraform.Output(t, terraformOptions, "vpc_id")
    assert.NotEmpty(t, vpcID)
}
```

### Run Tests

```bash
cd test
go test -v -timeout 30m -run TestVPCModule
```

Expected output:
```
=== RUN   TestVPCModule
    TestVPCModule: vpc_test.go:25: Running command terraform with args [init]
    TestVPCModule: vpc_test.go:28: Running command terraform with args [apply -auto-approve]
    TestVPCModule: vpc_test.go:31: Running command terraform with args [output -no-color -json vpc_id]
    TestVPCModule: vpc_test.go:33: vpc_id = vpc-0abc123
    TestVPCModule: vpc_test.go:35: Running command terraform with args [destroy -auto-approve]
--- PASS: TestVPCModule (180.25s)
PASS
```

---

## 7. Workspaces (Dev/Stage/Prod)

Workspaces let you maintain multiple state files for the same configuration.

```
terraform.tfstate.d/
├── dev/
│   └── terraform.tfstate
├── staging/
│   └── terraform.tfstate
└── prod/
    └── terraform.tfstate
```

### Workspace Commands

```bash
# List workspaces
terraform workspace list
# * default

# Create workspaces
terraform workspace new dev
terraform workspace new staging
terraform workspace new prod

# Switch workspace
terraform workspace select dev

# Show current workspace
terraform workspace show
# dev
```

### Using Workspaces in Configuration

```hcl
locals {
  env_config = {
    dev = {
      instance_type = "t3.micro"
      min_size      = 1
      max_size      = 2
    }
    staging = {
      instance_type = "t3.small"
      min_size      = 2
      max_size      = 4
    }
    prod = {
      instance_type = "t3.large"
      min_size      = 3
      max_size      = 10
    }
  }

  current_env = local.env_config[terraform.workspace]
}

resource "aws_instance" "web" {
  instance_type = local.current_env.instance_type

  tags = {
    Name        = "web-${terraform.workspace}"
    Environment = terraform.workspace
  }
}
```

### Workspaces with S3 Backend

```hcl
terraform {
  backend "s3" {
    bucket         = "mycompany-terraform-state"
    key            = "app/terraform.tfstate"   # workspace name auto-prepended
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
  }
}
```

State files in S3:
```
s3://mycompany-terraform-state/
  env:/dev/app/terraform.tfstate
  env:/staging/app/terraform.tfstate
  env:/prod/app/terraform.tfstate
```

> **Workspace vs Separate Directories:** Use workspaces when environments are nearly identical. Use separate directories (or Terragrunt) when environments have significantly different configurations.

---

## 8. Debugging Techniques

### State Inspection

```bash
# List all resources in state
terraform state list

# Show details of a specific resource
terraform state show aws_instance.web

# Pull the full state file (JSON)
terraform state pull > state.json
cat state.json | python3 -m json.tool | head -50

# Move a resource (rename without destroy/recreate)
terraform state mv aws_instance.old aws_instance.new

# Remove a resource from state (keep in AWS, stop managing)
terraform state rm aws_instance.decommissioned

# Import existing resource into state
terraform import aws_instance.existing i-0abc123def456
```

### Plan Analysis

```bash
# Save plan
terraform plan -out=tfplan

# Show plan in human-readable format
terraform show tfplan

# Show plan as JSON (for scripting)
terraform show -json tfplan | python3 -m json.tool

# Count changes by action type
terraform show -json tfplan | \
  python3 -c "
import json, sys
plan = json.load(sys.stdin)
actions = {}
for rc in plan.get('resource_changes', []):
    for a in rc['change']['actions']:
        actions[a] = actions.get(a, 0) + 1
for action, count in sorted(actions.items()):
    print(f'{action}: {count}')
"
```

### Targeted Operations

```bash
# Plan only specific resources
terraform plan -target=aws_instance.web

# Apply only specific resources (use sparingly)
terraform apply -target=module.network

# Refresh state without applying changes
terraform refresh
```

> **Warning:** `-target` should be used for debugging only, not as a regular workflow. It can leave state inconsistent.

---

## 9. Hands-On: Complete Terragrunt Setup

### Step 1: Create the Structure

```bash
mkdir -p ~/collab-lab/{modules/vpc,environments/{dev,staging}/vpc}
cd ~/collab-lab
```

### Step 2: Create the VPC Module

**modules/vpc/main.tf:**
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "environment" {
  type    = string
  default = "dev"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  }
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "vpc_cidr" {
  value = aws_vpc.main.cidr_block
}
```

### Step 3: Create Root terragrunt.hcl

**terragrunt.hcl:**
```hcl
remote_state {
  backend = "s3"
  config = {
    bucket         = "collab-lab-tf-state"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "us-east-1"
    }
  EOF
}
```

### Step 4: Create Environment Configs

**environments/dev/vpc/terragrunt.hcl:**
```hcl
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_repo_root()}/modules/vpc"
}

inputs = {
  vpc_cidr    = "10.0.0.0/16"
  environment = "dev"
}
```

**environments/staging/vpc/terragrunt.hcl:**
```hcl
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_repo_root()}/modules/vpc"
}

inputs = {
  vpc_cidr    = "10.1.0.0/16"
  environment = "staging"
}
```

### Step 5: Run Terragrunt

```bash
# Plan dev VPC
cd ~/collab-lab/environments/dev/vpc
terragrunt plan

# Plan all environments
cd ~/collab-lab/environments
terragrunt run-all plan
```

Expected output:
```
Group 1:
- Module: environments/dev/vpc
- Module: environments/staging/vpc

Terraform will perform the following actions:

  # aws_vpc.main will be created (dev: 10.0.0.0/16)
  # aws_vpc.main will be created (staging: 10.1.0.0/16)

Plan: 2 to add, 0 to change, 0 to destroy.
```

---

## 10. Summary

| Practice | Tool/Technique | Purpose |
|----------|---------------|---------|
| Version control | Git + .gitignore | Track changes, enable review |
| Secret protection | Secrets Manager, SSM, `sensitive` | Keep credentials out of git |
| Remote state | S3 + DynamoDB | Shared, locked, encrypted state |
| State sharing | `terraform_remote_state` | Cross-project references |
| DRY configs | Terragrunt | Eliminate copy-paste across envs |
| CI/CD | GitHub Actions / Jenkins | Automated plan/apply pipeline |
| Integration testing | Terratest (Go) | Real infrastructure validation |
| Environments | Workspaces or directories | Isolated dev/staging/prod |
| Debugging | `state list`, `show`, `TF_LOG` | Inspect and troubleshoot |
| Compliance | tfsec, checkov | Automated security scanning |

> **Key takeaway:** Collaboration at scale requires discipline. Use Git for history, Terragrunt for DRY, CI/CD for safety gates, remote state for sharing, and Secrets Manager for credentials. No team member should ever run `terraform apply` from their laptop against production.
