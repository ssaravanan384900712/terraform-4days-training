# Lab 1.5 - Resource Dependencies and Modules Introduction

Terraform automatically manages the order in which resources are created, updated, and destroyed based on their dependencies. Understanding how Terraform builds and resolves its dependency graph is essential for writing correct configurations. This lab covers implicit and explicit dependencies, the dependency graph, lifecycle rules, and introduces Terraform modules -- the primary mechanism for organizing and reusing infrastructure code.

---

## Prerequisites

- Completed Labs 1.2 through 1.4
- Terraform installed and AWS credentials configured

---

## 1. Creating Resources -- Block Syntax Review

Every resource in Terraform follows this syntax:

```hcl
resource "<PROVIDER>_<TYPE>" "<LOCAL_NAME>" {
  <ARGUMENT> = <VALUE>

  <NESTED_BLOCK> {
    <ARGUMENT> = <VALUE>
  }
}
```

### Components Explained

| Component | Example | Purpose |
|-----------|---------|---------|
| Provider | `aws` | Which provider plugin to use |
| Type | `instance` | Which resource type to create |
| Local name | `web_server` | Unique identifier within your config |
| Arguments | `ami = "ami-abc123"` | Configuration for the resource |
| Nested blocks | `tags { ... }` | Sub-configurations |

### Full Example

```hcl
resource "aws_instance" "web_server" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public.id      # Reference to another resource

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name        = "web-server"
    Environment = "dev"
  }
}
```

> **Tip:** The full resource address is `aws_instance.web_server`. You use this address in `terraform state` commands, `terraform import`, `-target` flags, and when referencing the resource from other resources.

---

## 2. Resource Dependencies

Terraform must know the order in which to create resources. There are two types of dependencies.

### 2.1 Implicit Dependencies (via References)

When one resource references another resource's attributes, Terraform automatically understands the dependency.

Set up the lab:

```bash
mkdir -p ~/terraform-labs/lab-1.5-dependencies
cd ~/terraform-labs/lab-1.5-dependencies
```

Create `providers.tf`:

```hcl
# providers.tf

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
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = "lab"
      ManagedBy   = "terraform"
      Lab         = "1.5"
    }
  }
}
```

Create `main.tf`:

```hcl
# main.tf - Implicit Dependencies

# ------------------------------------------------------------------
# Data Source: Latest Amazon Linux 2023 AMI
# ------------------------------------------------------------------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ------------------------------------------------------------------
# 1. VPC
# ------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "lab-1-5-vpc"
  }
}

# ------------------------------------------------------------------
# 2. Internet Gateway -- depends on VPC (implicit)
# ------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id   # <-- Implicit dependency on aws_vpc.main

  tags = {
    Name = "lab-1-5-igw"
  }
}

# ------------------------------------------------------------------
# 3. Subnet -- depends on VPC (implicit)
# ------------------------------------------------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id   # <-- Implicit dependency
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "lab-1-5-public-subnet"
  }
}

# ------------------------------------------------------------------
# 4. Route Table -- depends on VPC and IGW (implicit)
# ------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id   # <-- Implicit dependency on VPC

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id   # <-- Implicit dependency on IGW
  }

  tags = {
    Name = "lab-1-5-public-rt"
  }
}

# ------------------------------------------------------------------
# 5. Route Table Association -- depends on Subnet and Route Table
# ------------------------------------------------------------------
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id        # <-- Implicit dependency
  route_table_id = aws_route_table.public.id    # <-- Implicit dependency
}

# ------------------------------------------------------------------
# 6. Security Group -- depends on VPC (implicit)
# ------------------------------------------------------------------
resource "aws_security_group" "web" {
  name        = "lab-1-5-web-sg"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.main.id   # <-- Implicit dependency

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
    Name = "lab-1-5-web-sg"
  }
}

# ------------------------------------------------------------------
# 7. EC2 Instance -- depends on Subnet and Security Group (implicit)
# ------------------------------------------------------------------
resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id              # <-- Implicit
  vpc_security_group_ids = [aws_security_group.web.id]       # <-- Implicit

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    echo "<h1>Lab 1.5 - Dependencies</h1>" > /var/www/html/index.html
    systemctl start httpd
    systemctl enable httpd
  EOF

  tags = {
    Name = "lab-1-5-web-server"
  }
}
```

Create `outputs.tf`:

```hcl
# outputs.tf

output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnet_id" {
  value = aws_subnet.public.id
}

output "instance_id" {
  value = aws_instance.web.id
}

output "public_ip" {
  value = aws_instance.web.public_ip
}

output "web_url" {
  value = "http://${aws_instance.web.public_ip}"
}
```

### Initialize and plan

```bash
terraform init
terraform plan
```

**Expected output (summary):**
```
Plan: 7 to add, 0 to change, 0 to destroy.
```

Terraform figured out the correct creation order from the references:

```
1. VPC (no dependencies)
2. Internet Gateway, Subnet, Security Group (depend on VPC -- created in parallel)
3. Route Table (depends on VPC + IGW)
4. Route Table Association (depends on Subnet + Route Table)
5. EC2 Instance (depends on Subnet + Security Group)
```

### Apply

```bash
terraform apply -auto-approve
```

Watch the output -- you will see resources created in dependency order, with independent resources created in parallel.

---

## 3. Explicit Dependencies with depends_on

Sometimes Terraform cannot infer a dependency from the code. Use `depends_on` for these cases.

### When to Use depends_on

- When a dependency exists but is not reflected in resource attributes
- When a resource depends on a side effect of another resource
- When using provisioners that depend on other resources

### Example: S3 Bucket with IAM Policy

Add to `main.tf`:

```hcl
# ------------------------------------------------------------------
# Explicit Dependency Example
# ------------------------------------------------------------------

# IAM Role for EC2
resource "aws_iam_role" "ec2_role" {
  name = "lab-1-5-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "lab-1-5-ec2-role"
  }
}

# IAM Policy - grants S3 access
resource "aws_iam_role_policy" "s3_access" {
  name = "lab-1-5-s3-access"
  role = aws_iam_role.ec2_role.id   # <-- Implicit dependency on the role

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.app_data.arn,           # <-- Implicit dependency
          "${aws_s3_bucket.app_data.arn}/*"
        ]
      }
    ]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "lab-1-5-ec2-profile"
  role = aws_iam_role.ec2_role.name

  # Explicit dependency: wait for the policy to be attached before
  # creating the profile. Without this, the EC2 instance might launch
  # before the policy is ready.
  depends_on = [aws_iam_role_policy.s3_access]
}

# S3 Bucket for application data
resource "aws_s3_bucket" "app_data" {
  bucket_prefix = "lab-1-5-app-data-"

  tags = {
    Name = "lab-1-5-app-data"
  }
}

# EC2 Instance with IAM profile
resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  # Explicit dependency: ensure the route table association is complete
  # before launching the instance (so it has internet access via user_data)
  depends_on = [aws_route_table_association.public]

  user_data = <<-EOF
    #!/bin/bash
    echo "Instance with S3 access is ready"
  EOF

  tags = {
    Name = "lab-1-5-app-server"
  }
}
```

```bash
terraform plan
terraform apply -auto-approve
```

> **Warning:** Use `depends_on` sparingly. It forces sequential execution, which slows down Terraform. In most cases, implicit dependencies via references are sufficient and preferred. Only use `depends_on` when there is a true hidden dependency.

---

## 4. Dependency Graph

Terraform builds a Directed Acyclic Graph (DAG) of all resources and their dependencies. You can visualize this graph.

### 4.1 Generate the Graph

```bash
terraform graph
```

**Expected output (DOT format):**
```
digraph {
    compound = "true"
    newrank = "true"
    subgraph "root" {
        "[root] aws_instance.web (expand)" [label = "aws_instance.web", shape = "box"]
        "[root] aws_internet_gateway.main (expand)" [label = "aws_internet_gateway.main", shape = "box"]
        "[root] aws_route_table.public (expand)" [label = "aws_route_table.public", shape = "box"]
        "[root] aws_security_group.web (expand)" [label = "aws_security_group.web", shape = "box"]
        "[root] aws_subnet.public (expand)" [label = "aws_subnet.public", shape = "box"]
        "[root] aws_vpc.main (expand)" [label = "aws_vpc.main", shape = "box"]
        ...
        "[root] aws_instance.web (expand)" -> "[root] aws_security_group.web (expand)"
        "[root] aws_instance.web (expand)" -> "[root] aws_subnet.public (expand)"
        "[root] aws_internet_gateway.main (expand)" -> "[root] aws_vpc.main (expand)"
        "[root] aws_subnet.public (expand)" -> "[root] aws_vpc.main (expand)"
        ...
    }
}
```

### 4.2 Visualize the Graph

If you have Graphviz installed, convert the graph to an image:

```bash
# Install Graphviz (if not installed)
sudo apt install graphviz -y   # Ubuntu/Debian
# or
sudo yum install graphviz -y   # RHEL/Amazon Linux
# or
brew install graphviz           # macOS

# Generate a PNG image
terraform graph | dot -Tpng > dependency-graph.png

# Generate an SVG (better for large graphs)
terraform graph | dot -Tsvg > dependency-graph.svg
```

### 4.3 Graph for Plan and Destroy

```bash
# Graph for the current plan
terraform graph -type=plan

# Graph for destroy operations (shows reverse order)
terraform graph -type=destroy
```

> **Tip:** The dependency graph is particularly useful for debugging issues where resources are created in the wrong order or when you need to understand why Terraform wants to destroy and recreate something.

---

## 5. Lifecycle Rules

Lifecycle rules control how Terraform handles resource creation, updates, and destruction. They are declared inside a `lifecycle` block within a resource.

### 5.1 ignore_changes

Tells Terraform to ignore changes to specific attributes after the resource is created. This is useful when external processes (e.g., auto-scaling, manual changes) modify attributes that Terraform manages.

```hcl
resource "aws_instance" "example" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"

  tags = {
    Name = "lifecycle-example"
  }

  lifecycle {
    # Ignore changes to tags -- they may be modified by
    # external automation (e.g., AWS Config, cost allocation)
    ignore_changes = [tags]
  }
}
```

### Common ignore_changes Patterns

```hcl
# Ignore a single attribute
lifecycle {
  ignore_changes = [tags]
}

# Ignore multiple attributes
lifecycle {
  ignore_changes = [tags, ami, user_data]
}

# Ignore specific nested attributes
lifecycle {
  ignore_changes = [tags["LastModified"], tags["UpdatedBy"]]
}

# Ignore ALL changes (resource becomes read-only after creation)
lifecycle {
  ignore_changes = all
}
```

### 5.2 create_before_destroy

By default, Terraform destroys the old resource before creating the new one. This causes downtime. `create_before_destroy` reverses the order.

```hcl
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"

  lifecycle {
    # Create the replacement before destroying the original
    # This enables zero-downtime deployments
    create_before_destroy = true
  }

  tags = {
    Name = "zero-downtime-server"
  }
}
```

> **Tip:** `create_before_destroy` is essential for resources behind load balancers. The new instance can be registered with the LB before the old one is removed.

### 5.3 prevent_destroy

Prevents Terraform from destroying a resource. This is a safety net for critical resources.

```hcl
resource "aws_db_instance" "production" {
  allocated_storage = 100
  engine            = "mysql"
  instance_class    = "db.t3.medium"
  db_name           = "production"

  lifecycle {
    # Prevent accidental destruction of the production database
    prevent_destroy = true
  }
}
```

If you try to destroy this resource:

```bash
terraform destroy
```

**Expected error:**
```
Error: Instance cannot be destroyed

  on main.tf line XX:
  XX: resource "aws_db_instance" "production" {

Resource aws_db_instance.production has lifecycle.prevent_destroy set,
but the plan calls for this resource to be destroyed. To avoid this error
and destroy the resource, first remove the lifecycle.prevent_destroy
attribute from the configuration.
```

### 5.4 replace_triggered_by

Forces resource replacement when a specified resource or attribute changes.

```hcl
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"

  lifecycle {
    # Replace this instance whenever the security group changes
    replace_triggered_by = [
      aws_security_group.web.id
    ]
  }
}
```

### 5.5 Hands-On: Lifecycle Rules in Practice

Add to `main.tf`:

```hcl
# ------------------------------------------------------------------
# Lifecycle Rules Demo
# ------------------------------------------------------------------

resource "aws_instance" "lifecycle_demo" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]

  tags = {
    Name          = "lifecycle-demo"
    ManagedBy     = "terraform"
    LastManualEdit = "none"   # This might be changed manually
  }

  lifecycle {
    # Ignore the LastManualEdit tag -- it is managed outside Terraform
    ignore_changes = [tags["LastManualEdit"]]

    # Create new instance before destroying old one
    create_before_destroy = true
  }
}
```

```bash
terraform plan
terraform apply -auto-approve
```

Now, simulate an external change by modifying the tag via AWS CLI:

```bash
# Get the instance ID
INSTANCE_ID=$(terraform output -raw instance_id)

# Modify a tag externally
aws ec2 create-tags \
  --resources $INSTANCE_ID \
  --tags Key=LastManualEdit,Value="Modified by ops team"
```

Run plan again:

```bash
terraform plan
```

**Expected output:** No changes detected for the `LastManualEdit` tag because of `ignore_changes`.

---

## 6. Modules Introduction

Modules are the primary way to organize, reuse, and share Terraform code. Every Terraform configuration is technically a module -- the top-level one is called the **root module**.

### 6.1 Why Modules?

| Problem | Module Solution |
|---------|----------------|
| Code duplication | Write once, use many times |
| Long files | Break into logical components |
| No abstraction | Hide complexity behind clean interfaces |
| No reuse | Share modules across teams via registry |

### 6.2 Root Module vs Child Modules

```
project/
  main.tf           <-- ROOT MODULE (the top-level config)
  variables.tf
  outputs.tf
  modules/
    vpc/             <-- CHILD MODULE
      main.tf
      variables.tf
      outputs.tf
    ec2/             <-- CHILD MODULE
      main.tf
      variables.tf
      outputs.tf
```

### 6.3 Module Structure

Every module has three key files:

| File | Purpose |
|------|---------|
| `main.tf` | Resource definitions |
| `variables.tf` | Input variables (module's API) |
| `outputs.tf` | Output values (module's return values) |

---

## 7. Hands-On: Building Your First Module

### Step 1: Create the module directory structure

```bash
mkdir -p ~/terraform-labs/lab-1.5-modules
mkdir -p ~/terraform-labs/lab-1.5-modules/modules/web-server
cd ~/terraform-labs/lab-1.5-modules
```

### Step 2: Write the child module

Create `modules/web-server/variables.tf`:

```hcl
# modules/web-server/variables.tf

variable "server_name" {
  description = "Name for the web server"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "server_port" {
  description = "Port for the web server"
  type        = number
  default     = 80
}

variable "vpc_id" {
  description = "VPC ID where the server will be deployed"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the EC2 instance"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "extra_tags" {
  description = "Additional tags to apply"
  type        = map(string)
  default     = {}
}
```

Create `modules/web-server/main.tf`:

```hcl
# modules/web-server/main.tf

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  common_tags = merge(
    {
      Name        = var.server_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "web-server"
    },
    var.extra_tags
  )
}

# Security Group
resource "aws_security_group" "this" {
  name        = "${var.server_name}-sg"
  description = "Security group for ${var.server_name}"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = var.server_port
    to_port     = var.server_port
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

  tags = local.common_tags
}

# EC2 Instance
resource "aws_instance" "this" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    cat > /var/www/html/index.html << 'HTMLEOF'
    <html>
    <head><title>${var.server_name}</title></head>
    <body>
      <h1>${var.server_name}</h1>
      <p>Environment: ${var.environment}</p>
      <p>Instance Type: ${var.instance_type}</p>
    </body>
    </html>
    HTMLEOF
    sed -i 's/Listen 80/Listen ${var.server_port}/' /etc/httpd/conf/httpd.conf
    systemctl start httpd
    systemctl enable httpd
  EOF

  user_data_replace_on_change = true

  tags = local.common_tags
}
```

Create `modules/web-server/outputs.tf`:

```hcl
# modules/web-server/outputs.tf

output "instance_id" {
  description = "The EC2 instance ID"
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "The public IP address"
  value       = aws_instance.this.public_ip
}

output "private_ip" {
  description = "The private IP address"
  value       = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "The security group ID"
  value       = aws_security_group.this.id
}

output "url" {
  description = "The URL to access the web server"
  value       = "http://${aws_instance.this.public_ip}:${var.server_port}"
}
```

### Step 3: Write the root module that uses the child module

Create `providers.tf`:

```hcl
# providers.tf

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
  region = "us-east-1"

  default_tags {
    tags = {
      Lab       = "1.5-modules"
      ManagedBy = "terraform"
    }
  }
}
```

Create `main.tf`:

```hcl
# main.tf - Root Module

# ------------------------------------------------------------------
# Networking (inline for simplicity -- could be another module)
# ------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "lab-1-5-modules-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "lab-1-5-modules-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "lab-1-5-modules-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "lab-1-5-modules-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ------------------------------------------------------------------
# Module: Web Server (Dev)
# ------------------------------------------------------------------
module "web_server_dev" {
  source = "./modules/web-server"

  server_name   = "dev-web-server"
  instance_type = "t2.micro"
  server_port   = 8080
  vpc_id        = aws_vpc.main.id
  subnet_id     = aws_subnet.public.id
  environment   = "dev"

  extra_tags = {
    Team = "Development"
  }
}

# ------------------------------------------------------------------
# Module: Web Server (Staging)
# ------------------------------------------------------------------
module "web_server_staging" {
  source = "./modules/web-server"

  server_name   = "staging-web-server"
  instance_type = "t2.micro"
  server_port   = 8081
  vpc_id        = aws_vpc.main.id
  subnet_id     = aws_subnet.public.id
  environment   = "staging"

  extra_tags = {
    Team = "QA"
  }
}
```

Create `outputs.tf`:

```hcl
# outputs.tf - Root Module

# ------------------------------------------------------------------
# VPC Outputs
# ------------------------------------------------------------------
output "vpc_id" {
  description = "The VPC ID"
  value       = aws_vpc.main.id
}

# ------------------------------------------------------------------
# Dev Server Outputs (from module)
# ------------------------------------------------------------------
output "dev_instance_id" {
  description = "Dev server instance ID"
  value       = module.web_server_dev.instance_id
}

output "dev_public_ip" {
  description = "Dev server public IP"
  value       = module.web_server_dev.public_ip
}

output "dev_url" {
  description = "Dev server URL"
  value       = module.web_server_dev.url
}

# ------------------------------------------------------------------
# Staging Server Outputs (from module)
# ------------------------------------------------------------------
output "staging_instance_id" {
  description = "Staging server instance ID"
  value       = module.web_server_staging.instance_id
}

output "staging_public_ip" {
  description = "Staging server public IP"
  value       = module.web_server_staging.public_ip
}

output "staging_url" {
  description = "Staging server URL"
  value       = module.web_server_staging.url
}
```

### Step 4: Initialize and deploy

```bash
terraform init
```

**Expected output:**
```
Initializing the backend...
Initializing modules...
- web_server_dev in modules/web-server
- web_server_staging in modules/web-server
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.31.0...
- Installed hashicorp/aws v5.31.0 (signed by HashiCorp)

Terraform has been successfully initialized!
```

```bash
terraform plan
```

**Expected output (summary):**
```
Plan: 11 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + dev_instance_id     = (known after apply)
  + dev_public_ip       = (known after apply)
  + dev_url             = (known after apply)
  + staging_instance_id = (known after apply)
  + staging_public_ip   = (known after apply)
  + staging_url         = (known after apply)
  + vpc_id              = (known after apply)
```

```bash
terraform apply -auto-approve
```

### Step 5: Verify

```bash
terraform output

# Test dev server
curl $(terraform output -raw dev_url)

# Test staging server
curl $(terraform output -raw staging_url)
```

### Step 6: Inspect module resources in state

```bash
terraform state list
```

**Expected output:**
```
aws_internet_gateway.main
aws_route_table.public
aws_route_table_association.public
aws_subnet.public
aws_vpc.main
module.web_server_dev.aws_instance.this
module.web_server_dev.aws_security_group.this
module.web_server_dev.data.aws_ami.amazon_linux
module.web_server_staging.aws_instance.this
module.web_server_staging.aws_security_group.this
module.web_server_staging.data.aws_ami.amazon_linux
```

Notice how module resources are prefixed with `module.<name>.`.

```bash
# Show a specific module resource
terraform state show module.web_server_dev.aws_instance.this
```

---

## 8. Module Sources

Modules can be loaded from various sources:

### Local Path

```hcl
module "vpc" {
  source = "./modules/vpc"
}
```

### Terraform Registry

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.4.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"
}
```

### GitHub

```hcl
module "vpc" {
  source = "github.com/terraform-aws-modules/terraform-aws-vpc?ref=v5.4.0"
}
```

### S3 Bucket

```hcl
module "vpc" {
  source = "s3::https://s3-eu-west-1.amazonaws.com/my-modules/vpc.zip"
}
```

> **Tip:** For production, always pin module versions. Use the Terraform Registry for community modules -- they are tested, documented, and widely used. Browse available modules at **https://registry.terraform.io/browse/modules**.

---

## 9. Module Best Practices

| Practice | Description |
|----------|-------------|
| **Small, focused modules** | Each module should do one thing well |
| **Clear interface** | Use `variables.tf` for inputs, `outputs.tf` for return values |
| **Sensible defaults** | Provide defaults where possible, require only essentials |
| **Version pinning** | Always pin module versions in production |
| **Documentation** | Add `description` to every variable and output |
| **No hardcoded values** | Parameterize everything through variables |
| **Output everything useful** | Consumers may need IDs, ARNs, names, IPs |
| **Use locals** | Keep main.tf clean with computed values in locals |

---

## 10. Cleanup

Destroy all resources from both lab sections:

```bash
# Clean up the modules lab
cd ~/terraform-labs/lab-1.5-modules
terraform destroy -auto-approve

# Clean up the dependencies lab
cd ~/terraform-labs/lab-1.5-dependencies
terraform destroy -auto-approve
```

Verify everything is destroyed:

```bash
cd ~/terraform-labs/lab-1.5-modules && terraform state list
cd ~/terraform-labs/lab-1.5-dependencies && terraform state list
```

Both should return empty output.

---

## 11. Knowledge Check

1. What is the difference between implicit and explicit dependencies?
2. When should you use `depends_on`?
3. What does `ignore_changes = all` do?
4. How does `create_before_destroy` help with zero-downtime deployments?
5. What three files should every module contain?
6. How do you reference a module's output value?
7. What is the difference between a root module and a child module?

---

## Summary

| Topic | Key Takeaway |
|-------|-------------|
| Resource block syntax | `resource "provider_type" "name" { ... }` |
| Implicit dependencies | Created automatically from attribute references |
| Explicit dependencies | `depends_on` for hidden dependencies |
| Dependency graph | `terraform graph` to visualize resource ordering |
| ignore_changes | Prevent Terraform from reverting external changes |
| create_before_destroy | Zero-downtime replacements |
| prevent_destroy | Safety net for critical resources |
| Modules | Reusable, composable infrastructure components |
| Module interface | variables.tf (inputs), outputs.tf (return values) |
| Module sources | Local paths, Terraform Registry, GitHub, S3 |

This completes Day 1. You now have a solid foundation in Terraform -- from concepts through practical deployment, variables, dependencies, and modules. Day 2 will build on this with advanced resource patterns, state management, and real-world AWS architectures.
