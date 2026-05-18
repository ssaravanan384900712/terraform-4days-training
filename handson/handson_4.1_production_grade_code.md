# Hands-On 4.1 — Production-Grade Terraform Code

**File:** `~/lab4.1-prod-grade/`

---

## Concept

Most Terraform tutorials stop at `terraform apply` -- but production infrastructure demands far more discipline. This lab walks through the complete checklist that separates a weekend prototype from code that runs a business. You will refactor a monolithic `main.tf` into composable, testable, releasable modules following single-responsibility design.

### Production Readiness Spectrum

```
  Weekend Hack                                        Production Grade
  +-----------+----+----+----+----+----+----+----+----+-----------+
  | single    | no | no | no | no | no | no | no | no | composable|
  | main.tf   |pin |lock|env |IAM |CI  |test|mon |tag | modules   |
  +-----------+----+----+----+----+----+----+----+----+-----------+
       ^                                                    ^
       |                                                    |
   "it works                                         "it works at
    on my laptop"                                     3 AM when
                                                      I'm asleep"
```

### Production Checklist

| # | Category | What | Why |
|---|----------|------|-----|
| 1 | **Remote State** | S3 + DynamoDB backend | Collaboration, locking, durability |
| 2 | **Version Pinning** | `required_version`, `required_providers` | Reproducible builds |
| 3 | **State Locking** | DynamoDB lock table | Prevent concurrent corruption |
| 4 | **Environment Isolation** | Separate state per env | Blast-radius containment |
| 5 | **Least Privilege** | Scoped IAM for Terraform runner | Security boundary |
| 6 | **CI/CD Pipeline** | Automated plan/apply | Eliminate human error |
| 7 | **Testing** | `terraform test`, tfsec, checkov | Catch bugs before prod |
| 8 | **Monitoring** | CloudWatch alarms on infra | Know when things break |
| 9 | **Tagging** | Consistent tag schema | Cost allocation, ownership |
| 10 | **Documentation** | README, variable descriptions | Team onboarding |

---

## Part 1 — The Monolith (Before Refactoring)

This is a typical "everything in one file" configuration that works but is unmaintainable.

### Step 1: Create the monolith

```bash
mkdir -p ~/lab4.1-prod-grade/monolith && cd ~/lab4.1-prod-grade/monolith
```

```hcl
# main.tf -- The Monolith (DO NOT do this in production)

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "my-vpc" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = { Name = "public-b" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "my-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  name   = "web-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  ami                    = "ami-0c55b159cbfafe1f0"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.web.id]
  tags = { Name = "web-server" }
}
```

> **Problem:** 80+ lines, no reuse, no environment separation, hardcoded values everywhere, local state.

---

## Part 2 — Small Modules (Single Responsibility)

Each module does ONE thing. This is the Unix philosophy applied to infrastructure.

### Module Design Principles

```
  +------------------+     +------------------+     +------------------+
  |   modules/vpc    |     | modules/security |     | modules/compute  |
  |                  |     |                  |     |                  |
  |  - VPC           |     |  - SG rules      |     |  - EC2 instance  |
  |  - Subnets       |---->|  - NACLs         |---->|  - User data     |
  |  - IGW           |     |                  |     |  - EBS volumes   |
  |  - Route tables  |     |                  |     |                  |
  +------------------+     +------------------+     +------------------+
         |                        |                        |
         v                        v                        v
     vpc_id, subnet_ids       sg_id                   instance_id
     (outputs)                (outputs)               (outputs)
```

### Step 2: Create the module directory structure

```bash
mkdir -p ~/lab4.1-prod-grade/refactored/{modules/{vpc,security,compute},environments/{dev,staging,prod}}
cd ~/lab4.1-prod-grade/refactored
```

```
refactored/
  modules/
    vpc/
      main.tf
      variables.tf
      outputs.tf
    security/
      main.tf
      variables.tf
      outputs.tf
    compute/
      main.tf
      variables.tf
      outputs.tf
  environments/
    dev/
      main.tf
      variables.tf
      terraform.tfvars
      backend.tf
    staging/
      ...
    prod/
      ...
```

### Step 3: VPC Module

```hcl
# modules/vpc/variables.tf

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of public subnet CIDRs"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of AZs for subnets"
  type        = list(string)
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "project" {
  description = "Project name for tagging"
  type        = string
}
```

```hcl
# modules/vpc/main.tf

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project}-${var.environment}-vpc"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project}-${var.environment}-public-${count.index}"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${var.project}-${var.environment}-igw"
    Environment = var.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project}-${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
```

```hcl
# modules/vpc/outputs.tf

output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}
```

### Step 4: Security Module

```hcl
# modules/security/variables.tf

variable "vpc_id" {
  description = "VPC ID to create security groups in"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "allowed_ingress_ports" {
  description = "List of ports to allow inbound"
  type        = list(number)
  default     = [80, 443]
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed for ingress"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
```

```hcl
# modules/security/main.tf

resource "aws_security_group" "web" {
  name_prefix = "web-${var.environment}-"
  vpc_id      = var.vpc_id
  description = "Security group for web tier - ${var.environment}"

  dynamic "ingress" {
    for_each = var.allowed_ingress_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
      description = "Allow port ${ingress.value}"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "web-${var.environment}-sg"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
```

```hcl
# modules/security/outputs.tf

output "web_sg_id" {
  description = "Security group ID for web tier"
  value       = aws_security_group.web.id
}
```

### Step 5: Compute Module

```hcl
# modules/compute/variables.tf

variable "ami_id" {
  description = "AMI ID for the instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "subnet_id" {
  description = "Subnet to launch in"
  type        = string
}

variable "security_group_ids" {
  description = "List of SG IDs to attach"
  type        = list(string)
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "instance_count" {
  description = "Number of instances"
  type        = number
  default     = 1
}
```

```hcl
# modules/compute/main.tf

data "cloudinit_config" "web" {
  gzip          = false
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content      = <<-EOT
      #!/bin/bash
      yum update -y
      yum install -y httpd
      echo "<h1>${var.project} - ${var.environment}</h1>" > /var/www/html/index.html
      systemctl start httpd
      systemctl enable httpd
    EOT
  }
}

resource "aws_instance" "this" {
  count = var.instance_count

  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  user_data_base64       = data.cloudinit_config.web.rendered

  tags = {
    Name        = "${var.project}-${var.environment}-web-${count.index}"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
```

```hcl
# modules/compute/outputs.tf

output "instance_ids" {
  description = "List of instance IDs"
  value       = aws_instance.this[*].id
}

output "public_ips" {
  description = "List of public IPs"
  value       = aws_instance.this[*].public_ip
}
```

---

## Part 3 — Composable Modules (Wiring It Together)

### Step 6: Environment root module (dev)

```hcl
# environments/dev/backend.tf

terraform {
  backend "s3" {
    bucket         = "mycompany-terraform-state"
    key            = "dev/infrastructure.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

```hcl
# environments/dev/variables.tf

variable "aws_region" {
  default = "us-east-1"
}

variable "environment" {
  default = "dev"
}

variable "project" {
  default = "myapp"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}
```

```hcl
# environments/dev/main.tf

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
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project
      ManagedBy   = "terraform"
    }
  }
}

# --- Data source: latest Amazon Linux 2023 AMI ---
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# --- Compose modules ---
module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  availability_zones  = ["us-east-1a", "us-east-1b"]
  environment         = var.environment
  project             = var.project
}

module "security" {
  source = "../../modules/security"

  vpc_id                = module.vpc.vpc_id
  environment           = var.environment
  allowed_ingress_ports = [80, 443]
}

module "compute" {
  source = "../../modules/compute"

  ami_id             = data.aws_ami.al2023.id
  instance_type      = "t3.micro"
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_ids = [module.security.web_sg_id]
  environment        = var.environment
  project            = var.project
  instance_count     = 1
}
```

```hcl
# environments/dev/terraform.tfvars

aws_region  = "us-east-1"
environment = "dev"
project     = "myapp"
vpc_cidr    = "10.0.0.0/16"
```

### Dependency Flow

```
  terraform.tfvars
        |
        v
  +-----+------+
  | dev/main.tf |
  +-----+------+
        |
        +----------+-----------+
        |          |           |
        v          v           v
  module.vpc  module.security  module.compute
        |          ^               ^
        +----------+               |
        | vpc_id                   |
        +--------------------------+
          subnet_ids, sg_id
```

---

## Part 4 — Testable Module Design

Modules should be designed for testability from the start.

### Rules for Testable Modules

| Rule | Example |
|------|---------|
| No hardcoded regions | Pass `region` as variable |
| No hardcoded AMIs | Use data sources or variable |
| Meaningful outputs | Output everything a test needs to validate |
| Small blast radius | One module = one concern |
| Default values for optional params | Tests can call with minimal config |

### Example: Test-Friendly Module Interface

```hcl
# A testable module has sensible defaults so tests can be minimal:
module "vpc" {
  source = "../../modules/vpc"

  # Required -- must be set
  vpc_cidr   = "10.99.0.0/16"
  environment = "test"
  project     = "test-run"

  # Optional -- defaults work for tests
  # public_subnet_cidrs defaults to ["10.99.1.0/24"]
  # availability_zones  defaults to ["us-east-1a"]
}

# Test assertion: module.vpc.vpc_id is not empty
# Test assertion: length(module.vpc.public_subnet_ids) > 0
```

---

## Part 5 — Releasable Modules (Versioning)

### Semantic Versioning for Modules

```
  v1.2.3
  | | |
  | | +-- PATCH: bug fixes, no interface change
  | +---- MINOR: new features, backward compatible
  +------ MAJOR: breaking changes
```

### Step 7: Tag and release a module

```bash
# In the module's Git repo:
cd ~/lab4.1-prod-grade/refactored/modules/vpc

# Initialize as a standalone repo (for registry publishing)
git init
git add .
git commit -m "feat: initial VPC module"

# Tag with semver
git tag -a v1.0.0 -m "v1.0.0 - Initial release"

# Future changes
git tag -a v1.1.0 -m "v1.1.0 - Add private subnet support"
git tag -a v2.0.0 -m "v2.0.0 - BREAKING: rename vpc_cidr to cidr_block"
```

### Consuming versioned modules

```hcl
# Pin to exact version
module "vpc" {
  source  = "git::https://github.com/myorg/terraform-aws-vpc.git?ref=v1.2.0"
  # ...
}

# Pin to minor range (gets v1.2.x patches)
module "vpc" {
  source  = "app.terraform.io/myorg/vpc/aws"
  version = "~> 1.2.0"
  # ...
}
```

### CHANGELOG.md convention

```markdown
## [1.1.0] - 2026-05-15
### Added
- Private subnet support with NAT Gateway option
- Output for private_subnet_ids

## [1.0.0] - 2026-05-01
### Added
- Initial VPC module with public subnets
- Internet Gateway and route table
```

---

## Part 6 — Beyond Terraform Modules (Terragrunt)

When native modules are not enough, tools like **Terragrunt** add a composition layer.

### When to Consider Terragrunt

| Scenario | Native Terraform | Terragrunt |
|----------|-----------------|------------|
| Simple project, 1-3 envs | Good | Overkill |
| 10+ environments, DRY config | Verbose | Great |
| Cross-stack dependencies | `terraform_remote_state` | `dependency` blocks |
| Consistent backend config | Repeat per env | `generate` block |
| Run commands across modules | Manual | `run-all` |

### Terragrunt structure example

```
live/
  terragrunt.hcl          # Root config (backend, provider)
  dev/
    vpc/
      terragrunt.hcl      # source = "../../modules/vpc"
    compute/
      terragrunt.hcl      # depends_on = ["../vpc"]
  prod/
    vpc/
      terragrunt.hcl
    compute/
      terragrunt.hcl
```

```hcl
# live/dev/vpc/terragrunt.hcl
terraform {
  source = "../../../modules/vpc"
}

include "root" {
  path = find_in_parent_folders()
}

inputs = {
  vpc_cidr    = "10.0.0.0/16"
  environment = "dev"
  project     = "myapp"
}
```

```bash
# Apply everything in dev:
cd live/dev
terragrunt run-all apply

# Plan just one module:
cd live/dev/vpc
terragrunt plan
```

---

## Validation: Run the Refactored Code

```bash
cd ~/lab4.1-prod-grade/refactored/environments/dev

# Initialize (skip backend for local testing)
terraform init

# Validate module composition
terraform validate
```

Expected output:
```
Success! The configuration is valid.
```

```bash
# Plan to see what will be created
terraform plan
```

Expected output (abbreviated):
```
Plan: 8 to add, 0 to change, 0 to destroy.

  # module.vpc.aws_vpc.this will be created
  # module.vpc.aws_subnet.public[0] will be created
  # module.vpc.aws_subnet.public[1] will be created
  # module.vpc.aws_internet_gateway.this will be created
  # module.vpc.aws_route_table.public will be created
  # module.vpc.aws_route_table_association.public[0] will be created
  # module.vpc.aws_route_table_association.public[1] will be created
  # module.security.aws_security_group.web will be created
  # module.compute.aws_instance.this[0] will be created
```

> **Key Takeaway:** The refactored code creates the same infrastructure as the monolith, but each piece is reusable, testable, and independently versioned. The environment root module is a thin composition layer that wires modules together.

---

## Summary

| Concept | Key Point |
|---------|-----------|
| Production Checklist | 10 items: remote state, pins, locking, env isolation, IAM, CI, tests, monitoring, tags, docs |
| Small Modules | One module = one concern (VPC, security, compute) |
| Composable Modules | Root modules wire child modules via inputs/outputs |
| Testable Modules | Sensible defaults, meaningful outputs, no hardcoded values |
| Releasable Modules | Semver tags, changelogs, registry publishing |
| Beyond Modules | Terragrunt for DRY config at scale |
