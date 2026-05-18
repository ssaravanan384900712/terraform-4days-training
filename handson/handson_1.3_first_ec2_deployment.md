# Lab 1.3 - First EC2 Deployment

This lab is where Terraform gets real. You will deploy your first EC2 instance on AWS, then progressively enhance it by adding a security group, a web server with user_data, and input variables for configurability. You will also learn how to read Terraform state, handle updates, and cleanly destroy resources. Each section builds on the previous one, culminating in a complete deploy/update/destroy cycle.

---

## Prerequisites

- Terraform installed (Lab 1.2)
- AWS CLI configured with valid credentials (Lab 1.2)
- An AWS account with EC2 permissions

---

## 1. Deploy Your First EC2 Instance

### Step 1: Create the project directory

```bash
mkdir -p ~/terraform-labs/lab-1.3-ec2
cd ~/terraform-labs/lab-1.3-ec2
```

### Step 2: Write the provider configuration

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
      Lab         = "1.3-ec2"
    }
  }
}
```

### Step 3: Use a data source to find the latest AMI

Instead of hardcoding an AMI ID (which changes by region and over time), use a data source to dynamically look up the latest Amazon Linux 2023 AMI.

Create `main.tf`:

```hcl
# main.tf

# ------------------------------------------------------------------
# Data Source: Find the latest Amazon Linux 2023 AMI
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

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# ------------------------------------------------------------------
# Resource: EC2 Instance
# ------------------------------------------------------------------
resource "aws_instance" "my_first_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"

  tags = {
    Name = "my-first-terraform-server"
  }
}
```

### Step 4: Define outputs

Create `outputs.tf`:

```hcl
# outputs.tf

output "instance_id" {
  description = "The ID of the EC2 instance"
  value       = aws_instance.my_first_server.id
}

output "instance_public_ip" {
  description = "The public IP of the EC2 instance"
  value       = aws_instance.my_first_server.public_ip
}

output "instance_state" {
  description = "The state of the EC2 instance"
  value       = aws_instance.my_first_server.instance_state
}

output "ami_id" {
  description = "The AMI ID used for the instance"
  value       = data.aws_ami.amazon_linux.id
}

output "ami_name" {
  description = "The AMI name"
  value       = data.aws_ami.amazon_linux.name
}
```

### Step 5: Initialize

```bash
terraform init
```

**Expected output:**
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.31.0...
- Installed hashicorp/aws v5.31.0 (signed by HashiCorp)

Terraform has been successfully initialized!
```

### Step 6: Review the plan

```bash
terraform plan
```

**Expected output:**
```
data.aws_ami.amazon_linux: Reading...
data.aws_ami.amazon_linux: Read complete after 1s [id=ami-0abcdef1234567890]

Terraform used the selected providers to generate the following execution plan.

  # aws_instance.my_first_server will be created
  + resource "aws_instance" "my_first_server" {
      + ami                                  = "ami-0abcdef1234567890"
      + arn                                  = (known after apply)
      + associate_public_ip_address          = (known after apply)
      + availability_zone                    = (known after apply)
      + cpu_core_count                       = (known after apply)
      + cpu_threads_per_core                 = (known after apply)
      + get_password_data                    = false
      + host_id                              = (known after apply)
      + id                                   = (known after apply)
      + instance_initiated_shutdown_behavior = (known after apply)
      + instance_state                       = (known after apply)
      + instance_type                        = "t2.micro"
      + ipv6_address_count                   = (known after apply)
      + ipv6_addresses                       = (known after apply)
      + key_name                             = (known after apply)
      + monitoring                           = false
      + primary_network_interface_id         = (known after apply)
      + private_dns                          = (known after apply)
      + private_ip                           = (known after apply)
      + public_dns                           = (known after apply)
      + public_ip                            = (known after apply)
      + secondary_private_ips                = (known after apply)
      + security_groups                      = (known after apply)
      + subnet_id                            = (known after apply)
      + tags                                 = {
          + "Name" = "my-first-terraform-server"
        }
      + tenancy                              = (known after apply)
      + vpc_security_group_ids               = (known after apply)
      ...
    }

Plan: 1 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + ami_id             = "ami-0abcdef1234567890"
  + ami_name           = "al2023-ami-2023.3.20231218.0-kernel-6.1-x86_64"
  + instance_id        = (known after apply)
  + instance_public_ip = (known after apply)
  + instance_state     = (known after apply)
```

> **Tip:** Notice how data sources are read during the plan phase. The AMI ID is resolved before any resources are created.

### Step 7: Apply

```bash
terraform apply
```

Type `yes` when prompted.

**Expected output:**
```
data.aws_ami.amazon_linux: Reading...
data.aws_ami.amazon_linux: Read complete after 1s [id=ami-0abcdef1234567890]
aws_instance.my_first_server: Creating...
aws_instance.my_first_server: Still creating... [10s elapsed]
aws_instance.my_first_server: Still creating... [20s elapsed]
aws_instance.my_first_server: Still creating... [30s elapsed]
aws_instance.my_first_server: Creation complete after 33s [id=i-0abc123def4567890]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

ami_id             = "ami-0abcdef1234567890"
ami_name           = "al2023-ami-2023.3.20231218.0-kernel-6.1-x86_64"
instance_id        = "i-0abc123def4567890"
instance_public_ip = "54.210.123.45"
instance_state     = "running"
```

### Step 8: Verify in AWS Console or CLI

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=my-first-terraform-server" \
  --query "Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]" \
  --output table
```

**Expected output:**
```
---------------------------------------------
|            DescribeInstances              |
+----------------------+---------+----------+
|  i-0abc123def4567890 | running | 54.210.x |
+----------------------+---------+----------+
```

---

## 2. Deploy a Web Server with Security Group and user_data

Now let us enhance our instance to serve a web page. We need:
- A **security group** to allow HTTP traffic on port 8080
- A **user_data** script to install and start a simple web server

### Step 1: Update main.tf

Replace the content of `main.tf` with:

```hcl
# main.tf

# ------------------------------------------------------------------
# Data Source: Find the latest Amazon Linux 2023 AMI
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

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# ------------------------------------------------------------------
# Security Group: Allow HTTP on port 8080
# ------------------------------------------------------------------
resource "aws_security_group" "web_sg" {
  name        = "web-server-sg"
  description = "Allow HTTP inbound traffic on port 8080"

  ingress {
    description = "HTTP from anywhere"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-server-sg"
  }
}

# ------------------------------------------------------------------
# EC2 Instance: Web Server
# ------------------------------------------------------------------
resource "aws_instance" "web_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y python3
    cat > /home/ec2-user/index.html << 'HTMLEOF'
    <html>
      <head><title>Terraform Lab</title></head>
      <body>
        <h1>Hello from Terraform!</h1>
        <p>This web server was deployed using Infrastructure as Code.</p>
        <p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>
      </body>
    </html>
    HTMLEOF
    cd /home/ec2-user
    nohup python3 -m http.server 8080 &
  EOF

  user_data_replace_on_change = true

  tags = {
    Name = "terraform-web-server"
  }
}
```

### Step 2: Update outputs.tf

```hcl
# outputs.tf

output "instance_id" {
  description = "The ID of the EC2 instance"
  value       = aws_instance.web_server.id
}

output "instance_public_ip" {
  description = "The public IP of the EC2 instance"
  value       = aws_instance.web_server.public_ip
}

output "web_url" {
  description = "URL to access the web server"
  value       = "http://${aws_instance.web_server.public_ip}:8080"
}

output "security_group_id" {
  description = "The ID of the security group"
  value       = aws_security_group.web_sg.id
}
```

### Step 3: Plan and apply

```bash
terraform plan
```

You should see that Terraform wants to:
- **Destroy** the old `my_first_server` instance (it was removed from config)
- **Create** a new `web_server` instance
- **Create** a new `web_sg` security group

```bash
terraform apply
```

Type `yes` to confirm.

### Step 4: Test the web server

Wait about 60 seconds for the user_data script to complete, then:

```bash
# Get the URL from outputs
terraform output web_url

# Test with curl
curl $(terraform output -raw web_url)
```

**Expected output:**
```html
<html>
  <head><title>Terraform Lab</title></head>
  <body>
    <h1>Hello from Terraform!</h1>
    <p>This web server was deployed using Infrastructure as Code.</p>
    <p>Instance ID: i-0abc123def4567890</p>
  </body>
</html>
```

> **Tip:** If curl times out, the user_data script may still be running. Wait another minute and try again. Also verify that the security group is correctly allowing port 8080.

---

## 3. Deploy a Configurable Web Server Using Variables

Hardcoded values make configurations inflexible. Let us refactor to use variables.

### Step 1: Create variables.tf

```hcl
# variables.tf

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "server_port" {
  description = "The port the web server will listen on"
  type        = number
  default     = 8080
}

variable "server_name" {
  description = "Name tag for the EC2 instance"
  type        = string
  default     = "terraform-web-server"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}
```

### Step 2: Update providers.tf to use the variable

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
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      Lab         = "1.3-ec2"
    }
  }
}
```

### Step 3: Update main.tf to use variables

```hcl
# main.tf

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

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_security_group" "web_sg" {
  name        = "${var.server_name}-sg"
  description = "Allow HTTP inbound traffic on port ${var.server_port}"

  ingress {
    description = "HTTP from anywhere"
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.server_name}-sg"
  }
}

resource "aws_instance" "web_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y python3
    cat > /home/ec2-user/index.html << 'HTMLEOF'
    <html>
      <head><title>${var.server_name}</title></head>
      <body>
        <h1>Hello from ${var.server_name}!</h1>
        <p>Environment: ${var.environment}</p>
        <p>Instance Type: ${var.instance_type}</p>
        <p>Port: ${var.server_port}</p>
      </body>
    </html>
    HTMLEOF
    cd /home/ec2-user
    nohup python3 -m http.server ${var.server_port} &
  EOF

  user_data_replace_on_change = true

  tags = {
    Name = var.server_name
  }
}
```

### Step 4: Update outputs.tf

```hcl
# outputs.tf

output "instance_id" {
  description = "The ID of the EC2 instance"
  value       = aws_instance.web_server.id
}

output "instance_public_ip" {
  description = "The public IP of the EC2 instance"
  value       = aws_instance.web_server.public_ip
}

output "web_url" {
  description = "URL to access the web server"
  value       = "http://${aws_instance.web_server.public_ip}:${var.server_port}"
}

output "security_group_id" {
  description = "The ID of the security group"
  value       = aws_security_group.web_sg.id
}

output "environment" {
  description = "The deployment environment"
  value       = var.environment
}
```

### Step 5: Create a terraform.tfvars file

```hcl
# terraform.tfvars

aws_region    = "us-east-1"
instance_type = "t2.micro"
server_port   = 8080
server_name   = "my-configurable-web-server"
environment   = "dev"
```

### Step 6: Apply with variables

```bash
terraform plan
terraform apply
```

You can also override variables from the command line:

```bash
# Override a specific variable
terraform plan -var="server_port=9090"

# Override multiple variables
terraform plan -var="server_port=9090" -var="instance_type=t2.small"

# Use a different var file
terraform plan -var-file="production.tfvars"
```

---

## 4. Working with State

Terraform state is the single most important concept to understand. The state file (`terraform.tfstate`) is how Terraform knows what it has created and manages.

### 4.1 Examine the State File

```bash
# List all resources in state
terraform state list
```

**Expected output:**
```
data.aws_ami.amazon_linux
aws_instance.web_server
aws_security_group.web_sg
```

```bash
# Show details of a specific resource
terraform state show aws_instance.web_server
```

**Expected output:**
```
# aws_instance.web_server:
resource "aws_instance" "web_server" {
    ami                                  = "ami-0abcdef1234567890"
    arn                                  = "arn:aws:ec2:us-east-1:123456789012:instance/i-0abc123def4567890"
    associate_public_ip_address          = true
    availability_zone                    = "us-east-1a"
    cpu_core_count                       = 1
    cpu_threads_per_core                 = 1
    disable_api_stop                     = false
    disable_api_termination              = false
    ebs_optimized                        = false
    get_password_data                    = false
    hibernation                          = false
    id                                   = "i-0abc123def4567890"
    instance_initiated_shutdown_behavior = "stop"
    instance_state                       = "running"
    instance_type                        = "t2.micro"
    ...
}
```

### 4.2 View Outputs

```bash
# Show all outputs
terraform output

# Show a specific output
terraform output instance_public_ip

# Show raw value (no quotes) -- useful for scripting
terraform output -raw web_url
```

### 4.3 Inspect the State File Directly

```bash
# The state file is JSON
cat terraform.tfstate | python3 -m json.tool | head -30
```

> **Warning:** Never manually edit the state file. Always use `terraform state` commands to manipulate state. Manual edits can corrupt the state and cause data loss.

### 4.4 State Commands Reference

| Command | Purpose |
|---------|---------|
| `terraform state list` | List all resources |
| `terraform state show <resource>` | Show resource details |
| `terraform state mv <src> <dst>` | Rename a resource in state |
| `terraform state rm <resource>` | Remove a resource from state (does NOT destroy it) |
| `terraform state pull` | Pull remote state to stdout |
| `terraform state push` | Push local state to remote |
| `terraform refresh` | Sync state with real infrastructure |

---

## 5. Handling Updates

One of Terraform's most powerful features is its ability to handle updates gracefully. Let us explore the different types of updates.

### 5.1 In-Place Update (Non-Destructive)

Some changes can be applied without destroying the resource. For example, changing tags:

Edit `terraform.tfvars`:

```hcl
server_name = "my-updated-web-server"
```

```bash
terraform plan
```

**Expected output:**
```
  # aws_instance.web_server will be updated in-place
  ~ resource "aws_instance" "web_server" {
        id                                   = "i-0abc123def4567890"
      ~ tags                                 = {
          ~ "Name" = "my-configurable-web-server" -> "my-updated-web-server"
        }
      ~ tags_all                             = {
          ~ "Name" = "my-configurable-web-server" -> "my-updated-web-server"
        }
        # (28 unchanged attributes hidden)
        # (8 unchanged blocks hidden)
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

Notice the `~` symbol -- it means an **in-place update**. The instance stays running.

```bash
terraform apply
```

### 5.2 Destructive Update (Replace)

Some changes **require destroying and recreating** the resource. For example, changing the AMI or user_data (when `user_data_replace_on_change = true`):

Change the instance type in `terraform.tfvars`:

```hcl
instance_type = "t2.small"
```

```bash
terraform plan
```

**Expected output (instance type change is in-place on modern AWS):**
```
  # aws_instance.web_server will be updated in-place
  ~ resource "aws_instance" "web_server" {
        id                                   = "i-0abc123def4567890"
      ~ instance_type                        = "t2.micro" -> "t2.small"
        ...
    }
```

> **Tip:** The plan output uses symbols to tell you what will happen:
> - `+` = Create
> - `-` = Destroy
> - `~` = Update in-place
> - `-/+` = Destroy and recreate (replacement)
> - `<=` = Read (data source)

### 5.3 Force Replacement

You can force Terraform to replace a resource even when it would normally update in-place:

```bash
terraform plan -replace="aws_instance.web_server"
```

**Expected output:**
```
  # aws_instance.web_server will be replaced, as requested
-/+ resource "aws_instance" "web_server" {
      ~ arn                                  = "arn:aws:ec2:..." -> (known after apply)
      ~ id                                   = "i-0abc123..." -> (known after apply)
      ...
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

> **Tip:** `terraform apply -replace=RESOURCE` is the modern replacement for the old `terraform taint` command. Use it when you need a fresh instance (e.g., after a failed provisioning script).

---

## 6. Destroying Resources

### 6.1 Destroy Everything

```bash
terraform destroy
```

This shows a plan of everything that will be destroyed and asks for confirmation:

**Expected output:**
```
  # aws_instance.web_server will be destroyed
  - resource "aws_instance" "web_server" { ... }

  # aws_security_group.web_sg will be destroyed
  - resource "aws_security_group" "web_sg" { ... }

Plan: 0 to add, 0 to change, 2 to destroy.

Do you really want to destroy all resources?
  Enter a value: yes

aws_instance.web_server: Destroying... [id=i-0abc123def4567890]
aws_instance.web_server: Still destroying... [10s elapsed]
aws_instance.web_server: Still destroying... [20s elapsed]
aws_instance.web_server: Destruction complete after 31s
aws_security_group.web_sg: Destroying... [id=sg-0abc123def4567890]
aws_security_group.web_sg: Destruction complete after 1s

Destroy complete! Resources: 2 destroyed.
```

> **Note:** Terraform destroys resources in the correct order based on dependencies. The instance is destroyed before the security group because the instance depends on the security group.

### 6.2 Targeted Destroy

You can destroy specific resources without affecting others:

```bash
# Destroy only the EC2 instance (keep the security group)
terraform destroy -target=aws_instance.web_server
```

> **Warning:** Targeted operations should be used sparingly. They can leave your infrastructure in an inconsistent state where the code and reality don't match.

### 6.3 Auto-Approve (Use with Caution)

```bash
# Skip the confirmation prompt
terraform destroy -auto-approve
```

> **Warning:** `-auto-approve` skips the safety confirmation. Only use this in CI/CD pipelines or when you are absolutely sure. Never use it in production without careful consideration.

---

## 7. FULL LAB: Complete EC2 Deploy/Update/Destroy Cycle

This section is a self-contained end-to-end exercise. Follow every step.

### Step 1: Set up the project

```bash
rm -rf ~/terraform-labs/lab-1.3-full
mkdir -p ~/terraform-labs/lab-1.3-full
cd ~/terraform-labs/lab-1.3-full
```

### Step 2: Create providers.tf

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
    }
  }
}
```

### Step 3: Create variables.tf

```hcl
# variables.tf

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "server_port" {
  description = "HTTP port for the web server"
  type        = number
  default     = 8080
}
```

### Step 4: Create main.tf

```hcl
# main.tf

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

resource "aws_security_group" "lab_sg" {
  name        = "lab-1-3-full-sg"
  description = "Security group for Lab 1.3 full exercise"

  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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
    Name = "lab-1-3-full-sg"
  }
}

resource "aws_instance" "lab_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.lab_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    echo "<h1>Lab 1.3 - Version 1</h1>" > /tmp/index.html
    cd /tmp && nohup python3 -m http.server ${var.server_port} &
  EOF

  user_data_replace_on_change = true

  tags = {
    Name    = "lab-1-3-full-server"
    Version = "1"
  }
}
```

### Step 5: Create outputs.tf

```hcl
# outputs.tf

output "public_ip" {
  value = aws_instance.lab_server.public_ip
}

output "url" {
  value = "http://${aws_instance.lab_server.public_ip}:${var.server_port}"
}

output "instance_id" {
  value = aws_instance.lab_server.id
}
```

### Step 6: Deploy (Create)

```bash
terraform init
terraform fmt
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

> **Tip:** Using `-out=tfplan` saves the plan to a file. When you `apply tfplan`, Terraform applies exactly that plan without re-calculating or prompting for confirmation. This is the recommended workflow for production.

**Record the outputs:**
```bash
terraform output
```

### Step 7: Test the web server

```bash
# Wait about 30 seconds for user_data to complete
curl $(terraform output -raw url)
```

Expected: `<h1>Lab 1.3 - Version 1</h1>`

### Step 8: Update (In-Place Tag Change)

Change the Version tag in `main.tf`:

```hcl
  tags = {
    Name    = "lab-1-3-full-server"
    Version = "2"
  }
```

```bash
terraform plan
# You should see: 0 to add, 1 to change, 0 to destroy
terraform apply -auto-approve
```

### Step 9: Update (Replace -- Change user_data)

Update the user_data in `main.tf`:

```hcl
  user_data = <<-EOF
    #!/bin/bash
    echo "<h1>Lab 1.3 - Version 2 (Updated!)</h1><p>Deployed at: $(date)</p>" > /tmp/index.html
    cd /tmp && nohup python3 -m http.server ${var.server_port} &
  EOF
```

```bash
terraform plan
# You should see: 1 to add, 0 to change, 1 to destroy (replacement)
terraform apply -auto-approve
```

The instance is replaced (destroyed and recreated) because `user_data_replace_on_change = true`.

```bash
# Wait for the new instance to start, then test
curl $(terraform output -raw url)
```

Expected: `<h1>Lab 1.3 - Version 2 (Updated!)</h1><p>Deployed at: Mon Jan 15 ...</p>`

### Step 10: Inspect state

```bash
terraform state list
terraform state show aws_instance.lab_server
terraform state show aws_security_group.lab_sg
```

### Step 11: Destroy

```bash
terraform destroy
```

Type `yes` to confirm. Verify all resources are gone:

```bash
terraform state list
# Should output nothing

aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=lab-1-3-full-server" \
  --query "Reservations[].Instances[].[InstanceId,State.Name]" \
  --output table
# Should show "terminated" or no results
```

---

## 8. Common Errors and Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `Error: No valid credential sources found` | AWS credentials not configured | Run `aws configure` or set env vars |
| `Error: creating EC2 Instance: UnauthorizedOperation` | IAM user lacks permissions | Attach `AmazonEC2FullAccess` policy |
| `Error: Error launching source instance: VPCIdNotSpecified` | No default VPC in region | Create a default VPC or specify `subnet_id` |
| `Error: timeout while waiting for state to become 'running'` | Instance launch failure | Check AMI compatibility with instance type |
| `curl: (7) Failed to connect` | Security group or user_data issue | Verify SG rules and wait for user_data |

---

## Summary

| Task | What You Learned |
|------|-----------------|
| Data source for AMI | Dynamically find the latest AMI |
| EC2 instance | Deploy a basic compute resource |
| Security groups | Control network access |
| user_data | Bootstrap instances at launch |
| Variables | Make configurations reusable |
| State commands | Inspect and manage Terraform state |
| In-place updates | Change tags without replacing |
| Destructive updates | Replace instances when needed |
| Destroy | Clean up all resources |

In the next lab, you will dive deep into variables, expressions, and functions.
