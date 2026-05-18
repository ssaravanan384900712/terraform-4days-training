# Lab 2.1 — Configuration, Advanced Variables, and Data Sources

Terraform's power goes well beyond simple string variables. In this lab you will work with complex variable types (maps, lists, objects), understand how Terraform resolves variable precedence when the same variable is set in multiple places, query existing AWS infrastructure using **data sources**, and configure the `terraform` settings block to pin provider and Terraform versions. By the end you will have a working configuration that discovers existing resources at plan time and uses them to launch new infrastructure.

---

## Prerequisites

- AWS CLI configured with valid credentials
- Terraform >= 1.6 installed
- A default VPC in your target region (most accounts have one)

---

## Part 1 — Map and List Variable Types

### Step 1: Create the project structure

```bash
mkdir -p ~/lab2.1-data-sources && cd ~/lab2.1-data-sources
```

### Step 2: Define advanced variable types in `variables.tf`

```hcl
# variables.tf

# --- List Variable ---
variable "availability_zones" {
  description = "List of AZs to deploy into"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# --- Map Variable ---
variable "instance_tags" {
  description = "Map of tags to apply to instances"
  type        = map(string)
  default = {
    Environment = "dev"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

# --- Map of instance sizes per environment ---
variable "instance_type_map" {
  description = "Instance type per environment"
  type        = map(string)
  default = {
    dev     = "t2.micro"
    staging = "t2.small"
    prod    = "t2.medium"
  }
}

# --- Object Variable ---
variable "network_config" {
  description = "Network configuration object"
  type = object({
    vpc_cidr            = string
    enable_dns_support  = bool
    public_subnet_cidrs = list(string)
  })
  default = {
    vpc_cidr            = "10.0.0.0/16"
    enable_dns_support  = true
    public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  }
}

# --- Simple selector ---
variable "environment" {
  description = "Current environment name"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
```

### Step 3: Use list iteration in `main.tf`

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
  region = var.aws_region
}

# --- Iterate over a list to create subnets ---
resource "aws_subnet" "public" {
  count             = length(var.network_config.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.network_config.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.instance_tags, {
    Name = "public-subnet-${count.index}"
  })
}

resource "aws_vpc" "main" {
  cidr_block           = var.network_config.vpc_cidr
  enable_dns_support   = var.network_config.enable_dns_support
  enable_dns_hostnames = true

  tags = merge(var.instance_tags, {
    Name = "${var.environment}-vpc"
  })
}

# --- Use map lookup to select instance type ---
resource "aws_instance" "app" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type_map[var.environment]
  subnet_id     = aws_subnet.public[0].id

  tags = merge(var.instance_tags, {
    Name = "${var.environment}-app-server"
  })
}
```

### Step 4: Create an outputs file

```hcl
# outputs.tf

output "subnet_ids" {
  description = "List of created subnet IDs"
  value       = aws_subnet.public[*].id
}

output "selected_instance_type" {
  description = "Instance type selected for current environment"
  value       = var.instance_type_map[var.environment]
}

output "vpc_id" {
  value = aws_vpc.main.id
}
```

> **Tip:** The splat expression `aws_subnet.public[*].id` is shorthand for collecting an attribute from every element of a resource created with `count`.

---

## Part 2 — Variable Precedence

Terraform evaluates variables from multiple sources. The override order (lowest to highest priority) is:

1. Default value in the variable block
2. `terraform.tfvars` file (auto-loaded)
3. `*.auto.tfvars` files (auto-loaded, alphabetical order)
4. `-var-file=filename` flag
5. `-var 'name=value'` CLI flag
6. `TF_VAR_name` environment variable

> **Important:** A higher-priority source **completely replaces** the value from a lower-priority source. For maps, values are NOT merged -- the entire map is replaced.

### Step 5: Create multiple variable files to observe precedence

```bash
# terraform.tfvars  (auto-loaded, priority 2)
cat > terraform.tfvars <<'EOF'
environment = "staging"
aws_region  = "us-east-1"
EOF

# prod.auto.tfvars  (auto-loaded, priority 3)
cat > prod.auto.tfvars <<'EOF'
environment = "prod"
EOF
```

### Step 6: Test precedence with different methods

```bash
# Initialize first
terraform init

# Test 1: Only defaults + auto-loaded files
# prod.auto.tfvars overrides terraform.tfvars because *.auto.tfvars has higher priority
terraform plan -var-file=/dev/null 2>&1 | grep "selected_instance_type"
# Expected: instance_type = "t2.medium" (prod)

# Test 2: CLI -var flag overrides everything except env vars
terraform plan -var 'environment=dev' 2>&1 | grep "selected_instance_type"
# Expected: instance_type = "t2.micro" (dev)

# Test 3: Environment variable has HIGHEST priority
export TF_VAR_environment="staging"
terraform plan 2>&1 | grep "selected_instance_type"
# Expected: instance_type = "t2.small" (staging)
unset TF_VAR_environment
```

> **Note:** In practice, teams often use `terraform.tfvars` for shared defaults, environment-specific `.tfvars` files passed via `-var-file`, and `TF_VAR_*` for CI/CD overrides.

---

## Part 3 — Data Sources

Data sources let you **read** information from your cloud provider or other sources without managing those resources. They are declared with `data` blocks.

### Step 7: Add data sources to query existing infrastructure

Add these data source blocks to `main.tf` (or create a separate `data.tf`):

```hcl
# data.tf

# --- Query the latest Amazon Linux 2023 AMI ---
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

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# --- Query the default VPC ---
data "aws_vpc" "default" {
  default = true
}

# --- Query subnets in the default VPC ---
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- Get current caller identity ---
data "aws_caller_identity" "current" {}

# --- Get current region ---
data "aws_region" "current" {}

# --- Get available AZs ---
data "aws_availability_zones" "available" {
  state = "available"
}
```

### Step 8: Add outputs for data sources

Append to `outputs.tf`:

```hcl
output "latest_ami_id" {
  description = "Latest Amazon Linux 2023 AMI"
  value       = data.aws_ami.amazon_linux.id
}

output "latest_ami_name" {
  description = "AMI name"
  value       = data.aws_ami.amazon_linux.name
}

output "default_vpc_id" {
  description = "Default VPC ID"
  value       = data.aws_vpc.default.id
}

output "default_subnet_ids" {
  description = "Subnet IDs in default VPC"
  value       = data.aws_subnets.default.ids
}

output "account_id" {
  description = "Current AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  description = "ARN of the caller"
  value       = data.aws_caller_identity.current.arn
}

output "current_region" {
  description = "Current AWS region"
  value       = data.aws_region.current.name
}

output "available_azs" {
  description = "Available AZs in current region"
  value       = data.aws_availability_zones.available.names
}
```

### Step 9: Run plan and inspect data source results

```bash
terraform plan
```

Expected output (abbreviated):

```
data.aws_caller_identity.current: Reading...
data.aws_region.current: Reading...
data.aws_vpc.default: Reading...
data.aws_availability_zones.available: Reading...
data.aws_ami.amazon_linux: Reading...
data.aws_caller_identity.current: Read complete after 0s [id=123456789012]
data.aws_region.current: Read complete after 0s [id=us-east-1]
data.aws_vpc.default: Read complete after 0s [id=vpc-abc12345]
...

Changes to Outputs:
  + account_id          = "123456789012"
  + available_azs       = ["us-east-1a", "us-east-1b", "us-east-1c", ...]
  + caller_arn          = "arn:aws:iam::123456789012:user/student"
  + current_region      = "us-east-1"
  + default_vpc_id      = "vpc-abc12345"
  + latest_ami_id       = "ami-0abcdef1234567890"
```

---

## Part 4 — Practical Exercise: Launch an Instance Using Only Data Sources

### Step 10: Create a standalone configuration using data sources

Create a new file `instance-from-data.tf`:

```hcl
# instance-from-data.tf
# Launch an instance in the DEFAULT VPC using only data sources
# (no hardcoded VPC, subnet, or AMI IDs)

resource "aws_security_group" "web" {
  name        = "${var.environment}-web-sg"
  description = "Allow HTTP and SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-web-sg"
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type_map[var.environment]
  subnet_id              = tolist(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Hello from $(hostname)</h1>" > /var/www/html/index.html
  EOF

  tags = merge(var.instance_tags, {
    Name = "${var.environment}-web-server"
  })
}
```

> **Tip:** Notice that we did not hardcode any IDs. The AMI, VPC, and subnet are all discovered at plan time via data sources. This makes the configuration portable across accounts and regions.

---

## Part 5 — Terraform Settings Block

### Step 11: Understand the `terraform` configuration block

The `terraform {}` block configures Terraform itself. Review the one in `main.tf`:

```hcl
terraform {
  # Pin Terraform CLI version
  required_version = ">= 1.6.0, < 2.0.0"

  # Pin provider versions
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration (covered in Lab 2.5)
  # backend "s3" { ... }
}
```

Key settings:

| Setting              | Purpose                                           |
|----------------------|---------------------------------------------------|
| `required_version`   | Restrict which Terraform CLI versions can be used |
| `required_providers` | Declare provider source addresses and versions    |
| `backend`            | Configure where state is stored                   |

Version constraint syntax:

| Constraint | Meaning                              |
|------------|--------------------------------------|
| `= 1.6.0`  | Exactly version 1.6.0               |
| `>= 1.6.0` | Version 1.6.0 or newer              |
| `~> 5.0`   | Any 5.x version (>= 5.0, < 6.0)    |
| `>= 1.6, < 2.0` | Between 1.6 and 2.0 exclusive  |

### Step 12: Validate and apply

```bash
# Format the code
terraform fmt -recursive

# Validate syntax
terraform validate

# Plan (review the output carefully)
terraform plan -out=tfplan

# Apply
terraform apply tfplan
```

Expected apply output:

```
aws_vpc.main: Creating...
aws_vpc.main: Creation complete after 3s [id=vpc-0a1b2c3d4e5f]
aws_subnet.public[0]: Creating...
aws_subnet.public[1]: Creating...
aws_subnet.public[2]: Creating...
aws_security_group.web: Creating...
...
aws_instance.web: Creating...
aws_instance.web: Still creating... [10s elapsed]
aws_instance.web: Creation complete after 35s [id=i-0abc123def456]
aws_instance.app: Creation complete after 33s [id=i-0def789abc012]

Apply complete! Resources: 7 added, 0 changed, 0 destroyed.

Outputs:

account_id = "123456789012"
available_azs = tolist(["us-east-1a", "us-east-1b", "us-east-1c", ...])
caller_arn = "arn:aws:iam::123456789012:user/student"
...
```

---

## Part 6 — Clean Up

```bash
terraform destroy -auto-approve
```

---

## Summary

| Concept              | What You Learned                                                        |
|----------------------|-------------------------------------------------------------------------|
| List/Map variables   | Complex types enable iteration and environment-specific lookups         |
| Variable precedence  | CLI > env > .auto.tfvars > terraform.tfvars > defaults                 |
| Data sources         | Query existing resources (AMIs, VPCs, subnets, identity) at plan time  |
| terraform block      | Pin Terraform and provider versions for reproducible builds            |

> **Key takeaway:** Data sources make your Terraform configurations portable and dynamic. Instead of hardcoding AMI IDs or VPC IDs, let Terraform discover them. Combined with advanced variable types, you can build configurations that adapt to any environment without code changes.
