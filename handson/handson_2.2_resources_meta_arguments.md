# Lab 2.2 — Resource Blocks and Meta-Arguments

Every piece of infrastructure Terraform manages is represented by a **resource block**. Beyond the basic resource syntax, Terraform provides powerful **meta-arguments** that control how resources are created, updated, and destroyed. In this lab you will explore the full resource lifecycle (Create, Read, Update, Delete) and master every meta-argument: `depends_on`, `count`, `for_each`, `provider`, and `lifecycle`. Each section includes a complete hands-on exercise.

---

## Prerequisites

- Terraform >= 1.6 installed
- AWS CLI configured
- Familiarity with Lab 2.1 concepts

---

## Part 1 — Resource Block Syntax and Behavior

### Resource Block Structure

```hcl
resource "<PROVIDER>_<TYPE>" "<LOCAL_NAME>" {
  # Required and optional arguments
  argument1 = "value1"
  argument2 = "value2"

  # Nested block
  nested_block {
    key = "value"
  }

  # Meta-arguments (apply to ANY resource)
  depends_on = [...]
  count      = <number>
  for_each   = <map|set>
  provider   = <provider_alias>
  lifecycle  { ... }
}
```

### Resource Behavior (CRUD Lifecycle)

When you run `terraform apply`, Terraform determines which CRUD operation to perform for each resource:

| State vs Config      | Action      | Symbol in Plan |
|----------------------|-------------|----------------|
| Not in state         | **Create**  | `+`            |
| In state, unchanged  | **Read**    | (no change)    |
| In state, changed    | **Update**  | `~`            |
| In state, removed    | **Delete**  | `-`            |
| Changed, forces new  | **Replace** | `-/+` or `+/-` |

> **Note:** Some attribute changes force a resource to be destroyed and recreated (e.g., changing an EC2 instance's `ami`). Terraform shows this as `-/+` (destroy then create) or `+/-` (create then destroy if `create_before_destroy` is set).

---

## Part 2 — `depends_on` Meta-Argument

Terraform automatically determines dependencies by analyzing references between resources. The `depends_on` meta-argument is for **hidden dependencies** that Terraform cannot detect.

### Step 1: Create project

```bash
mkdir -p ~/lab2.2-meta-args && cd ~/lab2.2-meta-args
```

### Step 2: Write `main.tf` with explicit dependency

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

# The S3 bucket
resource "aws_s3_bucket" "app_data" {
  bucket = "lab22-app-data-${random_id.suffix.hex}"

  tags = {
    Name = "app-data-bucket"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

# IAM role that needs the bucket to exist first
# (Terraform cannot see this dependency from the policy JSON alone)
resource "aws_iam_role" "app_role" {
  name = "lab22-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  # Explicit dependency: ensure bucket exists before role policy references it
  depends_on = [aws_s3_bucket.app_data]
}

resource "aws_iam_role_policy" "app_policy" {
  name = "app-s3-access"
  role = aws_iam_role.app_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["s3:GetObject", "s3:PutObject"]
      Effect   = "Allow"
      Resource = "${aws_s3_bucket.app_data.arn}/*"
    }]
  })
}
```

### Step 3: Initialize and view the dependency graph

```bash
terraform init
terraform graph | head -30
```

Expected output (abbreviated):

```
digraph {
  compound = "true"
  ...
  "[root] aws_iam_role.app_role" -> "[root] aws_s3_bucket.app_data"
  "[root] aws_iam_role_policy.app_policy" -> "[root] aws_iam_role.app_role"
  ...
}
```

> **Tip:** Use `terraform graph | dot -Tpng > graph.png` (requires Graphviz) to visualize the dependency graph. The `depends_on` edge will appear even though there is no direct reference.

---

## Part 3 — `count` Meta-Argument

`count` lets you create multiple copies of a resource. Each copy is identified by its index (`count.index`).

### Step 4: Create `count-demo.tf`

```hcl
# count-demo.tf

variable "instance_count" {
  description = "Number of web servers to create"
  type        = number
  default     = 3
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

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_instance" "web" {
  count = var.instance_count

  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  subnet_id     = tolist(data.aws_subnets.default.ids)[count.index % length(data.aws_subnets.default.ids)]

  tags = {
    Name = "web-server-${count.index}"
    # count.index is zero-based: 0, 1, 2
  }
}

# --- Splat Expressions ---
output "instance_ids" {
  description = "All instance IDs (splat expression)"
  value       = aws_instance.web[*].id
}

output "instance_public_ips" {
  description = "All public IPs"
  value       = aws_instance.web[*].public_ip
}

# Access a specific instance
output "first_instance_id" {
  description = "First instance ID"
  value       = aws_instance.web[0].id
}
```

### Step 5: Plan and observe

```bash
terraform plan
```

Expected output:

```
Terraform will perform the following actions:

  # aws_instance.web[0] will be created
  + resource "aws_instance" "web" {
      + ami           = "ami-0abcdef1234567890"
      + instance_type = "t2.micro"
      + tags          = { "Name" = "web-server-0" }
      ...
    }

  # aws_instance.web[1] will be created
  ...

  # aws_instance.web[2] will be created
  ...

Plan: 3 to add, 0 to change, 0 to destroy.
```

> **Warning:** If you remove an item from the middle of a `count` list, all subsequent resources shift their index. For example, removing `web-server-1` causes `web-server-2` to become `[1]`, triggering a destroy and recreate. Use `for_each` when resource identity matters.

---

## Part 4 — `for_each` Meta-Argument

`for_each` iterates over a **map** or **set of strings**. Each instance is identified by its key, not a numeric index, which avoids the index-shifting problem.

### Step 6: Create `for-each-demo.tf`

```hcl
# for-each-demo.tf

variable "ec2_instances" {
  description = "Map of instances to create"
  type = map(object({
    instance_type = string
    az            = string
  }))
  default = {
    "web-frontend" = {
      instance_type = "t2.micro"
      az            = "us-east-1a"
    }
    "api-backend" = {
      instance_type = "t2.small"
      az            = "us-east-1b"
    }
    "worker" = {
      instance_type = "t2.medium"
      az            = "us-east-1c"
    }
  }
}

resource "aws_instance" "servers" {
  for_each = var.ec2_instances

  ami               = data.aws_ami.amazon_linux.id
  instance_type     = each.value.instance_type
  availability_zone = each.value.az

  tags = {
    Name = each.key
    Role = each.key
  }
}

# --- Outputs ---
output "server_details" {
  description = "Map of server name to instance ID"
  value = {
    for name, instance in aws_instance.servers :
    name => {
      id        = instance.id
      public_ip = instance.public_ip
      type      = instance.instance_type
    }
  }
}

# --- for_each with a set of strings ---
variable "iam_users" {
  description = "Set of IAM user names to create"
  type        = set(string)
  default     = ["developer-1", "developer-2", "developer-3"]
}

resource "aws_iam_user" "developers" {
  for_each = var.iam_users
  name     = each.value  # for sets, each.key == each.value
  path     = "/developers/"

  tags = {
    Team = "development"
  }
}

output "iam_user_arns" {
  value = {
    for name, user in aws_iam_user.developers :
    name => user.arn
  }
}
```

### Step 7: Plan and compare with count

```bash
terraform plan
```

Expected output:

```
  # aws_instance.servers["api-backend"] will be created
  + resource "aws_instance" "servers" {
      + instance_type     = "t2.small"
      + tags              = { "Name" = "api-backend", "Role" = "api-backend" }
      ...
    }

  # aws_instance.servers["web-frontend"] will be created
  ...

  # aws_instance.servers["worker"] will be created
  ...
```

> **Key difference from count:** Resources are keyed by name (`"api-backend"`, `"web-frontend"`) rather than index (`[0]`, `[1]`). Removing `"api-backend"` from the map only destroys that one resource; it does not shift other resources.

---

## Part 5 — `provider` Meta-Argument (Multi-Region Deployment)

You can configure multiple instances of the same provider using **aliases** and then select which provider a resource uses.

### Step 8: Create `multi-region.tf`

```hcl
# multi-region.tf

provider "aws" {
  alias  = "west"
  region = "us-west-2"
}

# Default provider (us-east-1) is already configured in main.tf

# S3 bucket in primary region (uses default provider)
resource "aws_s3_bucket" "primary" {
  bucket = "lab22-primary-${random_id.suffix.hex}"
  tags = {
    Name   = "primary-bucket"
    Region = "us-east-1"
  }
}

# S3 bucket in secondary region (uses aliased provider)
resource "aws_s3_bucket" "secondary" {
  provider = aws.west
  bucket   = "lab22-secondary-${random_id.suffix.hex}"
  tags = {
    Name   = "secondary-bucket"
    Region = "us-west-2"
  }
}

output "primary_bucket_region" {
  value = aws_s3_bucket.primary.region
}

output "secondary_bucket_region" {
  value = aws_s3_bucket.secondary.region
}
```

### Step 9: Plan to verify multi-region

```bash
terraform plan
```

You should see one bucket in us-east-1 and one in us-west-2.

> **Tip:** Provider aliasing is essential for multi-region disaster recovery setups, cross-region replication, and deploying global resources like CloudFront distributions alongside regional resources.

---

## Part 6 — `lifecycle` Meta-Argument

The `lifecycle` block customizes resource creation, update, and deletion behavior.

### Step 10: Create `lifecycle-demo.tf`

```hcl
# lifecycle-demo.tf

# --- create_before_destroy ---
# New resource is created BEFORE the old one is destroyed
# Essential for zero-downtime replacements
resource "aws_instance" "zero_downtime" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"

  tags = {
    Name = "zero-downtime-demo"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- prevent_destroy ---
# Terraform will error if you try to destroy this resource
# Protects critical infrastructure from accidental deletion
resource "aws_s3_bucket" "critical_data" {
  bucket = "lab22-critical-${random_id.suffix.hex}"

  tags = {
    Name        = "critical-data"
    Environment = "production"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# --- ignore_changes ---
# Terraform will not detect or revert changes to specified attributes
# Useful when external processes modify resources (e.g., autoscaling changes instance count)
resource "aws_instance" "managed_externally" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"

  tags = {
    Name      = "externally-managed"
    UpdatedBy = "terraform"
  }

  lifecycle {
    ignore_changes = [
      tags["UpdatedBy"],  # Ignore changes to this specific tag
      instance_type,       # Ignore if someone resizes manually
    ]
  }
}

# --- precondition and postcondition ---
variable "required_ami_owner" {
  default = "amazon"
}

resource "aws_instance" "validated" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"

  tags = {
    Name = "validated-instance"
  }

  lifecycle {
    precondition {
      condition     = data.aws_ami.amazon_linux.image_owner_alias == var.required_ami_owner
      error_message = "AMI must be owned by '${var.required_ami_owner}', got '${data.aws_ami.amazon_linux.image_owner_alias}'."
    }

    postcondition {
      condition     = self.public_ip != ""
      error_message = "Instance must have a public IP address assigned."
    }
  }
}

# --- replace_triggered_by ---
# Force replacement when another resource changes
resource "aws_instance" "app" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"

  tags = {
    Name = "app-with-trigger"
  }

  lifecycle {
    replace_triggered_by = [
      # Replace this instance whenever the security group changes
      aws_security_group.app_sg.id
    ]
  }
}

resource "aws_security_group" "app_sg" {
  name        = "lab22-app-sg"
  description = "App security group"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 443
    to_port     = 443
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
    Name = "lab22-app-sg"
  }
}
```

### Step 11: Test lifecycle behaviors

```bash
# Initialize with the random provider
terraform init -upgrade

# Apply everything
terraform apply -auto-approve

# Try to destroy the critical_data bucket
terraform destroy -target=aws_s3_bucket.critical_data
```

Expected error:

```
Error: Instance cannot be destroyed

  on lifecycle-demo.tf line XX:
  XX: resource "aws_s3_bucket" "critical_data" {

Resource aws_s3_bucket.critical_data has lifecycle.prevent_destroy set, but
the plan calls for this resource to be destroyed.
```

> **Important:** `prevent_destroy` only prevents destruction via Terraform. You can still delete the resource directly in the AWS console. To destroy it via Terraform, you must first remove the `prevent_destroy` setting from the config.

### Step 12: Test ignore_changes

```bash
# Manually change a tag in the AWS console or via CLI
aws ec2 create-tags \
  --resources $(terraform output -raw managed_externally_id 2>/dev/null || echo "i-placeholder") \
  --tags Key=UpdatedBy,Value=manual-update

# Plan again - Terraform will NOT show a diff for the UpdatedBy tag
terraform plan
# Expected: "No changes. Your infrastructure matches the configuration."
```

---

## Part 7 — Complete Lifecycle Summary Table

| Meta-Argument         | Purpose                                              | Common Use Case                     |
|-----------------------|------------------------------------------------------|-------------------------------------|
| `depends_on`          | Explicit dependency ordering                         | Hidden dependencies                 |
| `count`               | Create N copies of a resource                        | Multiple identical instances        |
| `for_each`            | Create instances from a map/set                      | Named resources with unique config  |
| `provider`            | Select a specific provider alias                     | Multi-region deployments            |
| `create_before_destroy` | Create replacement before destroying old          | Zero-downtime updates               |
| `prevent_destroy`     | Block terraform destroy                              | Protect databases, S3 buckets       |
| `ignore_changes`      | Ignore external modifications                        | Auto-scaled resources               |
| `precondition`        | Validate inputs before apply                         | Input validation                    |
| `postcondition`       | Validate outputs after apply                         | Ensure expected state               |
| `replace_triggered_by`| Force replacement when dependency changes            | Cascading updates                   |

---

## Clean Up

```bash
# First remove prevent_destroy from lifecycle-demo.tf, then:
terraform destroy -auto-approve
```

> **Tip:** Before running destroy, edit `lifecycle-demo.tf` and either remove the `prevent_destroy = true` line or change it to `false`. Otherwise the destroy command will fail for that resource.

---

## Summary

In this lab you learned the complete resource lifecycle in Terraform and practiced every meta-argument. The key insight is that `count` and `for_each` handle multiplicity, `depends_on` handles ordering, `provider` handles multi-region, and `lifecycle` handles behavioral customization. Choosing the right meta-argument for each situation is a fundamental Terraform skill.
