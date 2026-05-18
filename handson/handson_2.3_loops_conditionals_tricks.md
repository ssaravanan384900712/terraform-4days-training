# Lab 2.3 — Loops, Conditionals, and Terraform Tricks

Terraform's declarative language (HCL) is not a general-purpose programming language, but it provides surprisingly powerful constructs for loops, conditionals, and dynamic content generation. In this lab you will master `for` expressions to transform and filter collections, implement conditional resource creation with `count` and `for_each`, use dynamic blocks to generate repeated nested configuration, design zero-downtime deployments, and learn the most common Terraform gotchas that trip up even experienced practitioners.

---

## Prerequisites

- Terraform >= 1.6 installed
- AWS CLI configured
- Completed Labs 2.1 and 2.2

---

## Part 1 — `for` Expressions

`for` expressions let you transform one collection into another. They work on lists, maps, and sets.

### Step 1: Create project

```bash
mkdir -p ~/lab2.3-loops && cd ~/lab2.3-loops
```

### Step 2: Create `main.tf` with provider config

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
```

### Step 3: Create `for-expressions.tf`

```hcl
# for-expressions.tf

variable "server_names" {
  type    = list(string)
  default = ["web-1", "web-2", "api-1", "api-2", "worker-1"]
}

variable "users" {
  type = map(object({
    role       = string
    department = string
    active     = bool
  }))
  default = {
    "alice" = { role = "admin",     department = "engineering", active = true }
    "bob"   = { role = "developer", department = "engineering", active = true }
    "carol" = { role = "developer", department = "marketing",   active = false }
    "dave"  = { role = "admin",     department = "operations",  active = true }
    "eve"   = { role = "viewer",    department = "marketing",   active = true }
  }
}

# --- List transformation: uppercase all names ---
output "uppercase_names" {
  value = [for name in var.server_names : upper(name)]
  # Result: ["WEB-1", "WEB-2", "API-1", "API-2", "WORKER-1"]
}

# --- List filtering: only "web" servers ---
output "web_servers_only" {
  value = [for name in var.server_names : name if startswith(name, "web")]
  # Result: ["web-1", "web-2"]
}

# --- List to map transformation ---
output "server_index_map" {
  value = { for idx, name in var.server_names : name => idx }
  # Result: { "web-1" = 0, "web-2" = 1, "api-1" = 2, ... }
}

# --- Map filtering: only active users ---
output "active_users" {
  value = {
    for name, user in var.users :
    name => user.role
    if user.active
  }
  # Result: { "alice" = "admin", "bob" = "developer", "dave" = "admin", "eve" = "viewer" }
}

# --- Map filtering with multiple conditions ---
output "active_engineering_users" {
  value = [
    for name, user in var.users :
    name
    if user.active && user.department == "engineering"
  ]
  # Result: ["alice", "bob"]
}

# --- Grouping with for (groupby pattern) ---
output "users_by_department" {
  value = {
    for name, user in var.users :
    user.department => name...
    # The "..." groups values with the same key into a list
  }
  # Result: {
  #   "engineering" = ["alice", "bob"]
  #   "marketing"   = ["carol", "eve"]
  #   "operations"  = ["dave"]
  # }
}

# --- Nested for expressions ---
variable "environments" {
  default = ["dev", "staging", "prod"]
}

variable "services" {
  default = ["web", "api", "worker"]
}

output "all_service_names" {
  value = flatten([
    for env in var.environments : [
      for svc in var.services :
      "${env}-${svc}"
    ]
  ])
  # Result: ["dev-web", "dev-api", "dev-worker", "staging-web", ...]
}
```

### Step 4: Test the expressions

```bash
terraform init
terraform plan
```

Expected output (outputs section):

```
Changes to Outputs:
  + active_engineering_users = ["alice", "bob"]
  + active_users            = { "alice" = "admin", "bob" = "developer", ... }
  + all_service_names       = ["dev-web", "dev-api", "dev-worker", ...]
  + server_index_map        = { "api-1" = 2, "api-2" = 3, "web-1" = 0, ... }
  + uppercase_names         = ["WEB-1", "WEB-2", "API-1", "API-2", "WORKER-1"]
  + users_by_department     = { "engineering" = ["alice","bob"], ... }
  + web_servers_only        = ["web-1", "web-2"]
```

> **Tip:** Use `terraform console` to interactively test `for` expressions:
> ```
> $ terraform console
> > [for s in ["a","b","c"] : upper(s)]
> ["A", "B", "C"]
> ```

---

## Part 2 — Conditionals with `count`

The standard pattern for conditional resource creation is `count = <condition> ? 1 : 0`.

### Step 5: Create `conditionals.tf`

```hcl
# conditionals.tf

variable "create_monitoring" {
  description = "Whether to create monitoring resources"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "enable_enhanced_monitoring" {
  description = "Enable CloudWatch detailed monitoring"
  type        = bool
  default     = false
}

# --- Conditional resource creation ---
# Only create the SNS topic if monitoring is enabled
resource "aws_sns_topic" "alerts" {
  count = var.create_monitoring ? 1 : 0
  name  = "${var.environment}-alerts"

  tags = {
    Environment = var.environment
  }
}

# --- Conditional based on environment ---
# Only create a NAT gateway in production
resource "aws_eip" "nat" {
  count  = var.environment == "prod" ? 1 : 0
  domain = "vpc"

  tags = {
    Name = "nat-gateway-eip"
  }
}

# --- Conditional output ---
output "sns_topic_arn" {
  description = "SNS topic ARN (empty if monitoring disabled)"
  value       = var.create_monitoring ? aws_sns_topic.alerts[0].arn : "monitoring-disabled"
}

# --- Using a local for complex conditionals ---
locals {
  instance_type = (
    var.environment == "prod" ? "t2.large" :
    var.environment == "staging" ? "t2.medium" :
    "t2.micro"
  )

  # Conditional map merge
  base_tags = {
    ManagedBy = "terraform"
  }

  env_tags = var.environment == "prod" ? {
    Backup    = "daily"
    OnCall    = "true"
    CostCenter = "production"
  } : {}

  all_tags = merge(local.base_tags, local.env_tags)
}

output "resolved_instance_type" {
  value = local.instance_type
}

output "resolved_tags" {
  value = local.all_tags
}
```

### Step 6: Test conditionals

```bash
# Default: dev environment, monitoring enabled
terraform plan

# Production: see the NAT gateway EIP appear
terraform plan -var 'environment=prod'

# Disable monitoring
terraform plan -var 'create_monitoring=false'
```

---

## Part 3 — Complex Conditionals with `for_each`

### Step 7: Create `foreach-conditional.tf`

```hcl
# foreach-conditional.tf

variable "s3_buckets" {
  description = "Map of S3 buckets to conditionally create"
  type = map(object({
    enabled    = bool
    versioning = bool
    acl        = string
  }))
  default = {
    "logs" = {
      enabled    = true
      versioning = false
      acl        = "log-delivery-write"
    }
    "artifacts" = {
      enabled    = true
      versioning = true
      acl        = "private"
    }
    "temp-data" = {
      enabled    = false  # This bucket will NOT be created
      versioning = false
      acl        = "private"
    }
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Only create buckets where enabled = true
resource "aws_s3_bucket" "buckets" {
  for_each = {
    for name, config in var.s3_buckets :
    name => config
    if config.enabled
  }

  bucket = "lab23-${each.key}-${random_id.bucket_suffix.hex}"

  tags = {
    Name       = each.key
    Versioning = each.value.versioning ? "enabled" : "disabled"
  }
}

# Conditionally enable versioning only where configured
resource "aws_s3_bucket_versioning" "buckets" {
  for_each = {
    for name, config in var.s3_buckets :
    name => config
    if config.enabled && config.versioning
  }

  bucket = aws_s3_bucket.buckets[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

output "created_buckets" {
  value = {
    for name, bucket in aws_s3_bucket.buckets :
    name => bucket.id
  }
}
```

### Step 8: Plan to verify conditional for_each

```bash
terraform plan
```

Expected output:

```
  # aws_s3_bucket.buckets["artifacts"] will be created
  # aws_s3_bucket.buckets["logs"] will be created
  # aws_s3_bucket_versioning.buckets["artifacts"] will be created

Plan: 3 to add, 0 to change, 0 to destroy.
```

Notice: `temp-data` is skipped entirely because `enabled = false`.

---

## Part 4 — Dynamic Blocks

Dynamic blocks generate repeated nested blocks inside a resource. They are especially useful for security group rules, IAM policy statements, and other resources with variable-length nested configurations.

### Step 9: Create `dynamic-blocks.tf`

```hcl
# dynamic-blocks.tf

variable "security_group_rules" {
  description = "List of ingress rules for the security group"
  type = list(object({
    description = string
    port        = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = [
    {
      description = "SSH"
      port        = 22
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8"]
    },
    {
      description = "HTTP"
      port        = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "HTTPS"
      port        = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "Application"
      port        = 8080
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12"]
    }
  ]
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "dynamic_sg" {
  name        = "lab23-dynamic-sg"
  description = "Security group with dynamic rules"
  vpc_id      = data.aws_vpc.default.id

  # Dynamic block replaces repeated "ingress" blocks
  dynamic "ingress" {
    for_each = var.security_group_rules
    content {
      description = ingress.value.description
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lab23-dynamic-sg"
  }
}

output "dynamic_sg_id" {
  value = aws_security_group.dynamic_sg.id
}

# --- Advanced: Dynamic block with conditional ---
variable "enable_port_ranges" {
  type = list(object({
    from_port   = number
    to_port     = number
    description = string
    enabled     = bool
  }))
  default = [
    { from_port = 3000, to_port = 3999, description = "Dev ports",  enabled = true },
    { from_port = 5000, to_port = 5999, description = "Test ports", enabled = false },
    { from_port = 8000, to_port = 8999, description = "App ports",  enabled = true },
  ]
}

resource "aws_security_group" "conditional_dynamic" {
  name        = "lab23-conditional-dynamic-sg"
  description = "SG with conditional dynamic rules"
  vpc_id      = data.aws_vpc.default.id

  dynamic "ingress" {
    # Only include enabled rules
    for_each = [for rule in var.enable_port_ranges : rule if rule.enabled]
    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lab23-conditional-dynamic-sg"
  }
}
```

### Step 10: Plan and review dynamic blocks

```bash
terraform plan
```

Expected output shows each ingress rule expanded:

```
  # aws_security_group.dynamic_sg will be created
  + resource "aws_security_group" "dynamic_sg" {
      + ingress = [
          + { description = "SSH",  from_port = 22,   to_port = 22   ... },
          + { description = "HTTP", from_port = 80,   to_port = 80   ... },
          + { description = "HTTPS",from_port = 443,  to_port = 443  ... },
          + { description = "Application", from_port = 8080, to_port = 8080 ... },
        ]
    }
```

> **Tip:** Dynamic blocks should be used judiciously. Overusing them makes code harder to read. Use them when the number of nested blocks genuinely varies (like security group rules), not when you have a fixed set of blocks.

---

## Part 5 — Zero-Downtime Deployment Pattern

### Step 11: Create `zero-downtime.tf`

This pattern uses `create_before_destroy` with a Launch Template and Auto Scaling Group to achieve blue/green-style deployments.

```hcl
# zero-downtime.tf

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

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "lab23-app-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum install -y httpd
    systemctl start httpd
    echo "<h1>Version 1.0</h1>" > /var/www/html/index.html
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "lab23-app"
    }
  }

  # When the template changes, create the new one before destroying the old
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "lab23-app-${aws_launch_template.app.latest_version}"
  desired_capacity    = 2
  min_size            = 2
  max_size            = 4
  vpc_zone_identifier = tolist(data.aws_subnets.default.ids)

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # Wait for instances to be healthy before considering the ASG ready
  wait_for_capacity_timeout = "5m"

  tag {
    key                 = "Name"
    value               = "lab23-app"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}
```

> **How zero-downtime works:** When you change the `user_data` (e.g., update to "Version 2.0"), Terraform creates a new Launch Template version. The ASG uses `create_before_destroy`, so the new ASG with new instances spins up first, and only after they are healthy does the old ASG get destroyed. During the transition, both old and new instances serve traffic.

---

## Part 6 — Terraform Gotchas and Pitfalls

### Gotcha 1: Count Index Shift

```hcl
# PROBLEM: Removing an item from the middle shifts all indices

variable "servers" {
  default = ["web", "api", "worker"]
  # If you remove "api", "worker" shifts from [2] to [1]
  # Terraform destroys "api" AND recreates "worker" with new index
}

# SOLUTION: Use for_each instead of count when identity matters
resource "aws_instance" "servers" {
  for_each      = toset(var.servers)
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  tags = {
    Name = each.value
  }
}
# Now removing "api" only destroys that one resource
```

### Gotcha 2: Valid Plans That Fail on Apply

```hcl
# PROBLEM: Plan succeeds but apply fails
# Example: Creating a security group rule that conflicts with an existing rule

resource "aws_security_group_rule" "example" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.dynamic_sg.id
  # If this exact rule already exists (created outside Terraform),
  # plan shows "1 to add" but apply fails with a duplicate error.
}

# SOLUTION: Import existing resources before managing them
# terraform import aws_security_group_rule.example <sg-id>_ingress_tcp_80_80_0.0.0.0/0
```

### Gotcha 3: Refactoring Changes Resource Addresses

```hcl
# PROBLEM: Renaming a resource destroys and recreates it

# Before:
resource "aws_instance" "web_server" { ... }

# After (renamed):
resource "aws_instance" "application_server" { ... }

# Terraform sees: destroy "web_server", create "application_server"
# SOLUTION: Use "moved" block to tell Terraform about the rename
moved {
  from = aws_instance.web_server
  to   = aws_instance.application_server
}
```

### Gotcha 4: Eventual Consistency

```hcl
# PROBLEM: AWS API returns success, but resource is not fully propagated
# Common with IAM roles, policies, and DNS

resource "aws_iam_role" "example" {
  name = "example-role"
  assume_role_policy = jsonencode({ ... })
}

resource "aws_lambda_function" "example" {
  function_name = "example"
  role          = aws_iam_role.example.arn
  # Sometimes fails because IAM role is not yet propagated
  # even though Terraform created it successfully
}

# SOLUTION 1: Add a time_sleep resource
resource "time_sleep" "wait_for_iam" {
  depends_on      = [aws_iam_role.example]
  create_duration = "10s"
}

resource "aws_lambda_function" "example_fixed" {
  depends_on    = [time_sleep.wait_for_iam]
  function_name = "example"
  role          = aws_iam_role.example.arn
}

# SOLUTION 2: Re-run terraform apply (the retry often succeeds)
```

### Gotcha 5: Count/for_each Cannot Use Resource Outputs

```hcl
# PROBLEM: count/for_each must be known at plan time

# This FAILS because the data source query result is not known until apply:
# resource "aws_instance" "dynamic" {
#   count = length(data.aws_instances.existing.ids)
#   ...
# }

# SOLUTION: Use a variable or local value that is known at plan time
variable "instance_count" {
  default = 3
}

resource "aws_instance" "dynamic" {
  count         = var.instance_count
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
}
```

---

## Part 7 — Putting It All Together Exercise

### Step 12: Create `exercise.tf`

Build a multi-tier application infrastructure using everything you learned:

```hcl
# exercise.tf

variable "app_config" {
  description = "Application tier configuration"
  type = map(object({
    instance_count = number
    instance_type  = string
    port           = number
    public         = bool
  }))
  default = {
    "frontend" = {
      instance_count = 2
      instance_type  = "t2.micro"
      port           = 80
      public         = true
    }
    "backend" = {
      instance_count = 2
      instance_type  = "t2.small"
      port           = 8080
      public         = false
    }
    "database" = {
      instance_count = 1
      instance_type  = "t2.medium"
      port           = 5432
      public         = false
    }
  }
}

# Security group per tier using for_each + dynamic blocks
resource "aws_security_group" "tier" {
  for_each = var.app_config

  name        = "lab23-${each.key}-sg"
  description = "Security group for ${each.key} tier"
  vpc_id      = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = each.value.public ? [
      { port = each.value.port, cidr = ["0.0.0.0/0"] },
      { port = 22, cidr = ["10.0.0.0/8"] }
    ] : [
      { port = each.value.port, cidr = ["10.0.0.0/8"] }
    ]
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ingress.value.cidr
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lab23-${each.key}-sg"
    Tier = each.key
  }
}

# Instances per tier
resource "aws_instance" "tier" {
  for_each = {
    for pair in flatten([
      for tier_name, tier_config in var.app_config : [
        for i in range(tier_config.instance_count) : {
          key           = "${tier_name}-${i}"
          tier          = tier_name
          instance_type = tier_config.instance_type
        }
      ]
    ]) : pair.key => pair
  }

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = each.value.instance_type
  vpc_security_group_ids = [aws_security_group.tier[each.value.tier].id]

  tags = {
    Name = "lab23-${each.key}"
    Tier = each.value.tier
  }
}

output "tier_instances" {
  value = {
    for name, instance in aws_instance.tier :
    name => {
      id   = instance.id
      type = instance.instance_type
      tier = instance.tags["Tier"]
    }
  }
}
```

### Step 13: Apply and verify

```bash
terraform plan
terraform apply -auto-approve
```

Expected: 5 instances (2 frontend + 2 backend + 1 database) and 3 security groups.

---

## Clean Up

```bash
terraform destroy -auto-approve
```

---

## Summary

| Concept                  | Syntax / Pattern                                                  |
|--------------------------|-------------------------------------------------------------------|
| List for expression      | `[for item in list : transform(item)]`                           |
| Map for expression       | `{for k, v in map : k => transform(v)}`                         |
| Filter in for            | `[for item in list : item if condition]`                         |
| Grouping                 | `{for k, v in map : group_key => v...}`                          |
| Conditional resource     | `count = condition ? 1 : 0`                                     |
| Conditional for_each     | `for_each = {for k,v in map : k => v if v.enabled}`             |
| Dynamic block            | `dynamic "block_name" { for_each = ... content { ... } }`       |
| Zero-downtime            | `lifecycle { create_before_destroy = true }` on ASG/LT          |
| Avoid index shift        | Use `for_each` instead of `count` when identity matters          |
| Rename without destroy   | Use `moved { from = ... to = ... }` block                       |

> **Key takeaway:** Terraform's loops and conditionals are expression-based, not statement-based. Everything evaluates to a value. Once you internalize this functional style, you can build highly dynamic infrastructure configurations while keeping them readable and maintainable.
