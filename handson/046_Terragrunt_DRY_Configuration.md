# 046 — Terragrunt: DRY Terraform Configuration

**By:** Saravanan Sundaramoorthy
**Environment:** Local
**Time:** ~20 min

---

## Overview

Terragrunt is a thin wrapper around Terraform that adds DRY (Don't Repeat Yourself) patterns for managing multiple environments and modules. This lab covers the problem Terragrunt solves, installation, project structure, root and child configuration, key built-in functions, dependency blocks, and when to choose Terragrunt over Terraform workspaces or directory-per-environment layouts.

---

## The Problem Terragrunt Solves

Consider a project with three environments (dev, staging, prod) that each deploy the same S3 bucket module. Without Terragrunt you end up with this layout:

```
environments/
├── dev/
│   ├── main.tf          ← calls the module
│   ├── backend.tf       ← identical across all three
│   ├── providers.tf     ← identical across all three
│   └── terraform.tfvars ← environment-specific values
├── staging/
│   ├── main.tf          ← copy of dev/main.tf
│   ├── backend.tf       ← copy of dev/backend.tf
│   ├── providers.tf     ← copy of dev/providers.tf
│   └── terraform.tfvars
└── prod/
    ├── main.tf          ← copy of dev/main.tf
    ├── backend.tf       ← copy of dev/backend.tf
    ├── providers.tf     ← copy of dev/providers.tf
    └── terraform.tfvars
```

Every time the backend configuration changes (e.g., you add encryption to S3 state), you must update three files. Every time a provider version is pinned, you update three files. With ten modules across three environments that is thirty copies of essentially the same boilerplate.

Terragrunt solves this by:
1. Defining backend and provider configuration once in a root `terragrunt.hcl`
2. Letting child directories inherit the root configuration with `include`
3. Computing per-environment values using built-in functions like `path_relative_to_include()`
4. Adding `run-all` commands to plan or apply an entire environment tree at once

---

## Installation

```bash
# Check the latest release at https://github.com/gruntwork-io/terragrunt/releases
# Replace v0.55.0 with the current version

wget https://github.com/gruntwork-io/terragrunt/releases/download/v0.55.0/terragrunt_linux_amd64
chmod +x terragrunt_linux_amd64
sudo mv terragrunt_linux_amd64 /usr/local/bin/terragrunt

# Verify
terragrunt --version
# terragrunt version v0.55.0
```

On macOS:

```bash
brew install terragrunt
```

Terragrunt requires Terraform to be installed separately — it calls the `terraform` binary under the hood.

---

## Project Structure

The canonical Terragrunt project structure separates reusable modules from environment-specific configurations:

```
infrastructure/
├── terragrunt.hcl                    ← root config: shared backend + provider
├── modules/
│   └── s3-bucket/                    ← reusable module (pure Terraform)
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── environments/
    ├── dev/
    │   ├── terragrunt.hcl            ← dev-level defaults (optional)
    │   └── s3-bucket/
    │       └── terragrunt.hcl        ← calls s3-bucket module with dev values
    └── prod/
        ├── terragrunt.hcl            ← prod-level defaults (optional)
        └── s3-bucket/
            └── terragrunt.hcl        ← calls s3-bucket module with prod values
```

The key separation: `modules/` contains plain Terraform code with no Terragrunt awareness. `environments/` contains only `terragrunt.hcl` files — no `.tf` files. This keeps modules reusable without Terragrunt.

---

## Building the Lab

### Step 1: Create the directory structure

```bash
mkdir -p /tmp/tg-lab/infrastructure/modules/s3-bucket
mkdir -p /tmp/tg-lab/infrastructure/environments/dev/s3-bucket
mkdir -p /tmp/tg-lab/infrastructure/environments/prod/s3-bucket
cd /tmp/tg-lab/infrastructure
```

### Step 2: Write the reusable module (pure Terraform, no Terragrunt)

`modules/s3-bucket/variables.tf`:

```hcl
variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket (must be globally unique)"
}

variable "enable_versioning" {
  type        = bool
  default     = false
  description = "Enable S3 versioning"
}

variable "environment" {
  type        = string
  description = "Deployment environment: dev, staging, or prod"
}

variable "owner" {
  type        = string
  default     = "saravanans"
  description = "Owner tag value"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
```

`modules/s3-bucket/main.tf`:

```hcl
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Using local_file to simulate an S3 bucket for this lab
# (replace with aws_s3_bucket in a real project)

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  full_name = "${var.bucket_name}-${random_id.suffix.hex}"
  all_tags  = merge(var.tags, {
    Owner       = var.owner
    Environment = var.environment
    ManagedBy   = "Terragrunt"
  })
}

resource "local_file" "bucket_config" {
  filename = "/tmp/${local.full_name}.txt"
  content  = <<-EOT
    Simulated S3 Bucket Configuration
    ==================================
    Bucket Name:       ${local.full_name}
    Environment:       ${var.environment}
    Versioning:        ${var.enable_versioning}
    Owner:             ${var.owner}
    Tags:              ${jsonencode(local.all_tags)}
  EOT
}
```

`modules/s3-bucket/outputs.tf`:

```hcl
output "bucket_name" {
  value       = local.full_name
  description = "Full bucket name including random suffix"
}

output "config_file" {
  value       = local_file.bucket_config.filename
  description = "Path to the simulated bucket config file"
}
```

---

### Step 3: Root terragrunt.hcl

This file is the single source of truth for backend configuration and shared inputs. Every child `terragrunt.hcl` inherits from it.

`infrastructure/terragrunt.hcl`:

```hcl
# Root Terragrunt configuration
# All environments and modules inherit from this file via include "root"

remote_state {
  backend = "local"

  # generate: automatically write a backend.tf file in each working directory.
  # Terragrunt will place the state file at a path that includes the module's
  # relative path — so each module gets its own isolated state file.
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    # get_repo_root() returns the absolute path to the directory containing
    # the root terragrunt.hcl file.
    #
    # path_relative_to_include() returns the path from the root terragrunt.hcl
    # to the child terragrunt.hcl being processed.
    # Example: "environments/dev/s3-bucket"
    path = "${get_repo_root()}/.terragrunt-cache/${path_relative_to_include()}/terraform.tfstate"
  }
}

# Inputs defined here are passed to every module in every environment.
# Child terragrunt.hcl files can override any of these values.
inputs = {
  owner  = "saravanans"
  region = "ap-south-1"
}
```

**What `generate` does:** When Terragrunt processes a child directory, it writes a `backend.tf` file into that directory (inside `.terragrunt-cache/`) before calling `terraform init`. This means you never write a `backend.tf` by hand in any module — Terragrunt generates it from the root config.

---

### Step 4: Dev environment configuration

`environments/dev/terragrunt.hcl` (environment-level defaults, optional):

```hcl
# Optional: environment-level overrides that apply to all modules in dev.
# Child modules in this directory will inherit both the root config and this file.
# If you do not need environment-level defaults, this file can be omitted.

locals {
  environment = "dev"
  region      = "ap-south-1"
}
```

`environments/dev/s3-bucket/terragrunt.hcl`:

```hcl
# inherit the root terragrunt.hcl configuration
include "root" {
  path   = find_in_parent_folders()
  expose = true  # makes the root config accessible as include.root.inputs
}

terraform {
  # Terragrunt will download and cache this module source.
  # For local modules use a relative path with the "//" separator.
  # For remote modules use a Git URL:
  #   source = "git::https://github.com/org/modules.git//s3-bucket?ref=v1.0.0"
  source = "../../../modules/s3-bucket"
}

# These inputs are merged with the root inputs.
# Keys defined here override keys from the root config.
inputs = {
  bucket_name       = "robochef-dev-assets"
  enable_versioning = false
  environment       = "dev"
  tags = {
    Environment = "dev"
    Site        = "robochef.co"
    Owner       = "saravanans"
    CostCenter  = "engineering-dev"
  }
}
```

---

### Step 5: Prod environment configuration

`environments/prod/terragrunt.hcl`:

```hcl
locals {
  environment = "prod"
  region      = "ap-south-1"
}
```

`environments/prod/s3-bucket/terragrunt.hcl`:

```hcl
include "root" {
  path   = find_in_parent_folders()
  expose = true
}

terraform {
  source = "../../../modules/s3-bucket"
}

inputs = {
  bucket_name       = "robochef-prod-assets"
  enable_versioning = true   # versioning on in prod
  environment       = "prod"
  tags = {
    Environment = "prod"
    Site        = "robochef.co"
    Owner       = "saravanans"
    CostCenter  = "engineering-prod"
    Compliance  = "required"
  }
}
```

---

## Running Terragrunt Commands

### Single-module commands

From inside `environments/dev/s3-bucket/`:

```bash
cd /tmp/tg-lab/infrastructure/environments/dev/s3-bucket

# Initialize (downloads module source and providers)
terragrunt init

# Plan
terragrunt plan

# Apply
terragrunt apply

# Show outputs
terragrunt output

# Destroy
terragrunt destroy
rm -rf .terraform .terragrunt-cache
```

Terragrunt commands are identical to Terraform commands — it passes all flags and arguments through to `terraform` unchanged.

### run-all — operating on all modules at once

From the `infrastructure/` root:

```bash
cd /tmp/tg-lab/infrastructure

# Plan all modules in the entire directory tree
terragrunt run-all plan

# Apply all modules (Terragrunt respects dependency order)
terragrunt run-all apply

# Destroy all modules (in reverse dependency order)
terragrunt run-all destroy

# Plan only the dev environment
cd /tmp/tg-lab/infrastructure/environments/dev
terragrunt run-all plan
```

`run-all` discovers every directory containing a `terragrunt.hcl` file and runs the command in each, in dependency order. If there are no dependencies defined, it runs them in parallel.

---

## 6. Key Built-in Functions

Terragrunt provides helper functions that make the root config reusable across any project structure:

### find_in_parent_folders()

Walks up the directory tree from the current `terragrunt.hcl` and returns the path to the first `terragrunt.hcl` it finds. This is how child configs locate the root config without hardcoding paths:

```hcl
include "root" {
  path = find_in_parent_folders()
}
```

If the file is at `/infra/environments/dev/s3-bucket/terragrunt.hcl`, this returns `/infra/terragrunt.hcl`.

### path_relative_to_include()

Returns the path from the included file (root) to the current file. Used in the root config to generate unique state file paths:

```hcl
# In root terragrunt.hcl, when processing environments/dev/s3-bucket/terragrunt.hcl:
path_relative_to_include()
# Returns: "environments/dev/s3-bucket"
```

This ensures each module's state file is stored in a unique location.

### get_repo_root()

Returns the absolute path to the root of the Git repository (or the directory containing the root `terragrunt.hcl`):

```hcl
path = "${get_repo_root()}/.terragrunt-cache/${path_relative_to_include()}/terraform.tfstate"
```

### get_env()

Reads an environment variable, with an optional default:

```hcl
inputs = {
  aws_account_id = get_env("AWS_ACCOUNT_ID", "123456789012")
  environment    = get_env("TF_ENV", "dev")
}
```

### run_cmd()

Runs a shell command and uses the output as a value:

```hcl
locals {
  account_id = run_cmd("aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text")
}
```

---

## 7. dependency Blocks — Module Chaining

When one module depends on the outputs of another (e.g., a database module that needs a VPC ID from a network module), use the `dependency` block:

```hcl
# environments/dev/database/terragrunt.hcl

include "root" {
  path = find_in_parent_folders()
}

# Declare a dependency on the network module
dependency "network" {
  config_path = "../network"   # relative path to the other module's terragrunt.hcl

  # mock_outputs are used during plan when the dependency has not been applied yet.
  # This lets you run terragrunt run-all plan on a fresh environment.
  mock_outputs = {
    vpc_id     = "vpc-mock-00000000"
    subnet_ids = ["subnet-mock-0000", "subnet-mock-0001"]
  }
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
}

terraform {
  source = "../../../modules/database"
}

inputs = {
  vpc_id     = dependency.network.outputs.vpc_id
  subnet_ids = dependency.network.outputs.subnet_ids
  db_name    = "robochef-dev"
}
```

When `terragrunt run-all apply` encounters this, it applies the `network` module first, then the `database` module using the real VPC ID from network's outputs.

---

## 8. Terragrunt vs Workspaces vs Directories

| Approach | Best For | Downside |
|----------|----------|---------|
| **Terraform workspaces** | Identical configuration with only variable differences; same backend | State for all workspaces is in the same bucket/file — one accident can affect all environments; modules must be identical |
| **Directory per environment** (plain Terraform) | Simple projects, few environments | Backend and provider boilerplate is copied in every directory |
| **Terragrunt** | Many environments, many modules, team-managed infrastructure | Adds a tool dependency; learning curve for `find_in_parent_folders()` and `run-all` |

### When NOT to use Terragrunt

- Small projects with one environment
- Projects where the team has no Go or Terragrunt experience and the overhead outweighs the benefit
- Projects that use Terraform Cloud / HCP Terraform, which has built-in workspace and variable management

### When Terragrunt is worth it

- Three or more environments with shared backend and provider configuration
- Teams that release Terraform modules independently and want to version them
- Projects where `run-all` across an environment tree saves significant CI/CD time

---

## 9. Full Lab Walkthrough

```bash
# 1. Set up the directory structure (already done above)
cd /tmp/tg-lab/infrastructure

# 2. Apply the dev environment
cd environments/dev/s3-bucket
terragrunt init
terragrunt apply -auto-approve
terragrunt output

# 3. Apply the prod environment
cd /tmp/tg-lab/infrastructure/environments/prod/s3-bucket
terragrunt init
terragrunt apply -auto-approve
terragrunt output

# 4. Use run-all to plan both environments at once
cd /tmp/tg-lab/infrastructure
terragrunt run-all plan

# 5. Show the generated backend.tf files (Terragrunt writes these)
find /tmp/tg-lab -name "backend.tf" 2>/dev/null

# 6. Show the isolated state files
find /tmp/tg-lab -name "terraform.tfstate" 2>/dev/null

# 7. Destroy all environments
cd /tmp/tg-lab/infrastructure
terragrunt run-all destroy --terragrunt-non-interactive

# 8. Clean up
rm -rf /tmp/tg-lab
```

---

## 10. Terragrunt Caching

Terragrunt copies your module source into a cache directory (`.terragrunt-cache/`) before running Terraform. This is important to understand because:

- `terraform.tfstate` lives inside the cache, not in your source directory
- Running `terraform` commands directly inside your source directory will NOT use the root-generated `backend.tf`
- Always use `terragrunt` commands, not `terraform` commands, in Terragrunt projects

To clear the cache:

```bash
find . -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null
```

---

## Summary

| Concept | What It Does |
|---------|-------------|
| Root `terragrunt.hcl` | Defines backend and shared inputs once for all modules |
| `include "root"` | Inherits root config in a child `terragrunt.hcl` |
| `find_in_parent_folders()` | Locates root `terragrunt.hcl` without hardcoded paths |
| `path_relative_to_include()` | Generates unique state file paths per module per environment |
| `get_repo_root()` | Absolute path to the repo root for stable cache paths |
| `dependency {}` | Reads outputs from another Terragrunt module |
| `mock_outputs` | Provides fake values during plan when dependencies are not applied |
| `run-all plan/apply` | Operates on all modules in a directory tree in dependency order |
| `terraform.source` | Path or Git URL to the module being deployed |
