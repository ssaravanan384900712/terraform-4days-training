---
theme: default
title: 'Terraform Automation HandsOn Training with AWS'
info: |
  ## Terraform Automation HandsOn Training with AWS
  4-Day Comprehensive Training Program
author: Cloud Training Team
keywords: terraform,aws,iac,devops,automation
exportFilename: terraform-training-4days
export:
  format: pdf
  dark: false
highlighter: shiki
lineNumbers: true
drawings:
  persist: false
transition: slide-left
mdc: true
vite:
  server:
    allowedHosts: true
layout: cover
background: https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=1920
class: text-center
---

# 🚀 Terraform Automation

## HandsOn Training with AWS

<div class="pt-8">
  <span class="px-4 py-2 rounded-full bg-blue-500 text-white text-lg font-bold">
    4-Day Intensive Program
  </span>
</div>

<div class="abs-br m-6 flex gap-2">
  <span class="px-3 py-1 rounded bg-green-500 text-white text-sm">IaC</span>
  <span class="px-3 py-1 rounded bg-orange-500 text-white text-sm">AWS</span>
  <span class="px-3 py-1 rounded bg-purple-500 text-white text-sm">DevOps</span>
</div>

<div class="abs-bl m-6 text-left text-sm opacity-80">
  Infrastructure as Code | Automation | Cloud Native
</div>

---
transition: fade-out
layout: intro
class: text-left
---

# Course Overview

<div class="grid grid-cols-2 gap-8 pt-4">

<div>

## 📋 What You'll Learn

- **Infrastructure as Code** principles & practices
- **Terraform** CLI, HCL, providers & modules
- **AWS** resource provisioning & management
- **Team workflows**, CI/CD & GitOps
- **Security**, testing & production-grade patterns
- **Terraform Cloud** & Enterprise

</div>

<div>

## ⏱️ Schedule

| Day | Focus |
|-----|-------|
| **Day 1** | Foundations, Variables, EC2 |
| **Day 2** | Language, State & Backend |
| **Day 3** | Teams, Modules, Scaling |
| **Day 4** | Production, Security, Cloud |

<br>

> **Duration:** 4 Days × 4 Hours Each

</div>

</div>

---
class: text-center flex flex-col items-center justify-center
---

# <span class="text-blue-600">DAY 1</span>
## Terraform & IaC Foundations, Variables, EC2 Setup

<div class="pt-4">
  <span class="px-6 py-3 rounded-xl bg-gradient-to-r from-blue-500 to-cyan-500 text-white text-xl font-bold shadow-lg">
    Getting Started with Infrastructure as Code
  </span>
</div>

---
transition: slide-up
layout: two-cols
---

# The Rise of DevOps

<v-clicks>

- **Traditional Model**: Dev writes code → Ops deploys
- **The Problem**: Slow releases, blame culture, silos
- **DevOps Solution**: Shared responsibility, automation

</v-clicks>

<v-click>

<div class="mt-4 p-3 bg-blue-50 text-gray-800 rounded-lg border-l-4 border-blue-500">
  <strong>Key Principle:</strong> Automate everything — including infrastructure!
</div>

</v-click>

::right::

<div class="pl-8 pt-2">

```mermaid {scale: 0.42}
graph TD
    A[Plan] --> B[Code]
    B --> C[Build]
    C --> D[Test]
    D --> E[Release]
    E --> F[Deploy]
    F --> G[Operate]
    G --> H[Monitor]
    H --> A
    style A fill:#3B82F6,color:#fff
    style B fill:#8B5CF6,color:#fff
    style C fill:#EC4899,color:#fff
    style D fill:#F59E0B,color:#fff
    style E fill:#10B981,color:#fff
    style F fill:#3B82F6,color:#fff
    style G fill:#8B5CF6,color:#fff
    style H fill:#EC4899,color:#fff
```

</div>

---
transition: slide-left
---

# What Is Infrastructure as Code?

<div class="grid grid-cols-3 gap-6 pt-4">

<v-click>

<div class="p-4 bg-red-50 text-gray-800 rounded-xl border-2 border-red-200 text-center">
  <div class="text-3xl mb-2">🖱️</div>
  <h3 class="text-red-600 font-bold">Manual (Old Way)</h3>
  <p class="text-xs mt-2">Click through console, SSH into servers, run commands manually</p>
  <div class="mt-2 px-2 py-1 bg-red-100 rounded text-red-700 text-xs">❌ Error-prone & slow</div>
</div>

</v-click>

<v-click>

<div class="p-4 bg-yellow-50 text-gray-800 rounded-xl border-2 border-yellow-200 text-center">
  <div class="text-3xl mb-2">📜</div>
  <h3 class="text-yellow-600 font-bold">Scripts (Better)</h3>
  <p class="text-xs mt-2">Bash/Python scripts to automate, but hard to maintain</p>
  <div class="mt-2 px-2 py-1 bg-yellow-100 rounded text-yellow-700 text-xs">⚠️ Fragile & stateless</div>
</div>

</v-click>

<v-click>

<div class="p-4 bg-green-50 text-gray-800 rounded-xl border-2 border-green-200 text-center">
  <div class="text-3xl mb-2">📝</div>
  <h3 class="text-green-600 font-bold">IaC (Best)</h3>
  <p class="text-xs mt-2">Declarative code defines desired state — tools handle the rest</p>
  <div class="mt-2 px-2 py-1 bg-green-100 rounded text-green-700 text-xs">✅ Reliable & versioned</div>
</div>

</v-click>

</div>

<v-click>

<div class="mt-4 p-3 bg-blue-50 text-gray-800 rounded-lg border-l-4 border-blue-500 text-sm">
  <strong>Definition:</strong> IaC is managing infrastructure through machine-readable definition files, rather than manual configuration.
</div>

</v-click>

---

# Ad Hoc Scripts — The Starting Point

<div class="grid grid-cols-2 gap-6">
<div>

### Example: Bash Setup Script

```bash
#!/bin/bash
sudo apt-get update
sudo apt-get install -y nginx
sudo cp /tmp/nginx.conf /etc/nginx/nginx.conf
sudo systemctl start nginx
sudo systemctl enable nginx
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

</div>
<div>

### Limitations

<v-clicks>

- ❌ **Not idempotent** — running twice may break things
- ❌ **No state tracking** — don't know what's deployed
- ❌ **Hard to maintain** — scripts grow complex fast
- ❌ **No rollback** — can't undo changes easily
- ❌ **Platform-specific** — tied to one OS/cloud
- ❌ **No dependency management** — ordering is manual

</v-clicks>

</div>
</div>

<v-click>

<div class="mt-2 p-2 bg-orange-50 text-gray-800 rounded-lg border-l-4 border-orange-500 text-sm">
  <strong>Takeaway:</strong> Scripts work for small tasks, but don't scale for infrastructure management.
</div>

</v-click>

---
layout: two-cols
transition: slide-up
---

# Config Management Tools

<v-clicks>

### Chef
- Ruby DSL, Client-server model
- "Recipes" and "Cookbooks"

### Puppet
- Declarative language, Agent-based
- Strong compliance enforcement

### Ansible
- Agentless (SSH), YAML playbooks
- Great for config management

</v-clicks>

::right::

<div class="pl-8 pt-4">

<v-click>

### Ansible Example

```yaml
- hosts: webservers
  become: yes
  tasks:
    - name: Install nginx
      apt:
        name: nginx
        state: present
        update_cache: yes
    - name: Start nginx
      service:
        name: nginx
        state: started
        enabled: yes
```

</v-click>

<v-click>

<div class="mt-4 p-3 bg-purple-50 text-gray-800 rounded-lg border-l-4 border-purple-500 text-sm">
  <strong>Key Point:</strong> Config management tools configure <em>existing</em> servers. They don't provision infrastructure.
</div>

</v-click>

</div>

---

# Server Provisioning Tools

<div class="grid grid-cols-3 gap-4 pt-2">

<v-click>

<div class="p-3 bg-purple-50 text-gray-800 rounded-xl border-2 border-purple-200">
  <div class="text-center text-2xl mb-1">🏗️</div>
  <h3 class="text-purple-700 font-bold text-center text-sm">Terraform</h3>
  <ul class="text-xs mt-2 space-y-1">
    <li>✅ Multi-cloud support</li>
    <li>✅ Declarative HCL</li>
    <li>✅ State management</li>
    <li>✅ Huge ecosystem</li>
  </ul>
</div>

</v-click>

<v-click>

<div class="p-3 bg-orange-50 text-gray-800 rounded-xl border-2 border-orange-200">
  <div class="text-center text-2xl mb-1">☁️</div>
  <h3 class="text-orange-700 font-bold text-center text-sm">CloudFormation</h3>
  <ul class="text-xs mt-2 space-y-1">
    <li>✅ AWS-native</li>
    <li>⚠️ AWS-only</li>
    <li>✅ Deep AWS integration</li>
    <li>⚠️ Verbose JSON/YAML</li>
  </ul>
</div>

</v-click>

<v-click>

<div class="p-3 bg-green-50 text-gray-800 rounded-xl border-2 border-green-200">
  <div class="text-center text-2xl mb-1">💻</div>
  <h3 class="text-green-700 font-bold text-center text-sm">Pulumi</h3>
  <ul class="text-xs mt-2 space-y-1">
    <li>✅ Real programming languages</li>
    <li>✅ Multi-cloud</li>
    <li>⚠️ Smaller ecosystem</li>
    <li>⚠️ Newer entrant</li>
  </ul>
</div>

</v-click>

</div>

<v-click>

<div class="mt-4 p-3 bg-purple-50 text-gray-800 rounded-lg text-center">
  <strong class="text-purple-700">This course focuses on Terraform — the industry standard for multi-cloud IaC</strong>
</div>

</v-click>

---

# Benefits of Infrastructure as Code

<div class="grid grid-cols-2 gap-3 pt-2">

<v-click>

<div class="flex items-start gap-2 p-2 bg-blue-50 text-gray-800 rounded-lg">
  <span class="text-xl">⚡</span>
  <div>
    <h4 class="font-bold text-blue-700 text-sm">Speed & Efficiency</h4>
    <p class="text-xs">Deploy entire environments in minutes, not days</p>
  </div>
</div>

</v-click>

<v-click>

<div class="flex items-start gap-2 p-2 bg-green-50 text-gray-800 rounded-lg">
  <span class="text-xl">🔄</span>
  <div>
    <h4 class="font-bold text-green-700 text-sm">Consistency</h4>
    <p class="text-xs">Every deployment is identical — no configuration drift</p>
  </div>
</div>

</v-click>

<v-click>

<div class="flex items-start gap-2 p-2 bg-purple-50 text-gray-800 rounded-lg">
  <span class="text-xl">📋</span>
  <div>
    <h4 class="font-bold text-purple-700 text-sm">Version Control</h4>
    <p class="text-xs">Track every change, review PRs, rollback if needed</p>
  </div>
</div>

</v-click>

<v-click>

<div class="flex items-start gap-2 p-2 bg-orange-50 text-gray-800 rounded-lg">
  <span class="text-xl">🔁</span>
  <div>
    <h4 class="font-bold text-orange-700 text-sm">Repeatability</h4>
    <p class="text-xs">Reproduce any environment — dev, staging, prod</p>
  </div>
</div>

</v-click>

<v-click>

<div class="flex items-start gap-2 p-2 bg-red-50 text-gray-800 rounded-lg">
  <span class="text-xl">📖</span>
  <div>
    <h4 class="font-bold text-red-700 text-sm">Self-Documenting</h4>
    <p class="text-xs">Code IS the documentation of your infrastructure</p>
  </div>
</div>

</v-click>

<v-click>

<div class="flex items-start gap-2 p-2 bg-teal-50 text-gray-800 rounded-lg">
  <span class="text-xl">🤝</span>
  <div>
    <h4 class="font-bold text-teal-700 text-sm">Collaboration</h4>
    <p class="text-xs">Teams work together using Git workflows</p>
  </div>
</div>

</v-click>

</div>

---
transition: view-transition
layout: two-cols
---

# How Terraform Works

<v-clicks>

1. **Write** — Define resources in `.tf` files
2. **Init** — Download providers & init backend
3. **Plan** — Preview changes before applying
4. **Apply** — Execute and provision resources
5. **State** — Terraform tracks what it manages

</v-clicks>

::right::

<div class="pl-6 pt-2">

```mermaid {scale: 0.55}
graph TD
    A["📝 Write .tf"] --> B["⚙️ init"]
    B --> C["🔍 plan"]
    C --> D{"Review"}
    D -->|Approve| E["🚀 apply"]
    D -->|Reject| A
    E --> F["💾 State Updated"]
    F --> G["☁️ Infra Created"]
    G -->|Modify| A
    G -->|Destroy| H["💥 destroy"]
    style A fill:#3B82F6,color:#fff
    style B fill:#8B5CF6,color:#fff
    style C fill:#F59E0B,color:#fff
    style E fill:#10B981,color:#fff
    style F fill:#EC4899,color:#fff
    style G fill:#06B6D4,color:#fff
    style H fill:#EF4444,color:#fff
```

</div>

---

# Terraform vs Other Tools

| Feature | Terraform | CloudFormation | Ansible | Puppet |
|---------|-----------|---------------|---------|--------|
| **Type** | Provisioning | Provisioning | Config Mgmt | Config Mgmt |
| **Language** | HCL (Declarative) | JSON/YAML | YAML (Procedural) | Custom DSL |
| **State** | Managed | AWS-managed | Stateless | Master DB |
| **Multi-Cloud** | ✅ Yes | ❌ AWS only | ✅ Yes | ✅ Yes |
| **Agent** | Agentless | Agentless | Agentless | Agent-based |
| **Master** | Masterless | AWS service | Masterless | Master server |
| **Mutability** | Immutable | Immutable | Mutable | Mutable |

<v-click>

<div class="mt-4 p-3 bg-gradient-to-r from-blue-50 to-purple-50 rounded-lg border-l-4 border-blue-500">
  <strong>Why Terraform?</strong> Platform agnostic + Declarative + Immutable + Masterless + Agentless
</div>

</v-click>

---
class: text-center flex flex-col items-center justify-center
---

# <span class="text-green-600">Terraform Setup & First Use</span>

<div class="pt-4">
  <span class="px-6 py-3 rounded-xl bg-gradient-to-r from-green-500 to-emerald-500 text-white text-xl font-bold shadow-lg">
    Hands-On: Your First Terraform Deployment
  </span>
</div>

---

# Set Up AWS Account

<div class="grid grid-cols-2 gap-6">
<div>

### Prerequisites

<v-clicks>

1. **AWS Account** — Free tier eligible
2. **IAM User** — With programmatic access
3. **Access Keys** — `AWS_ACCESS_KEY_ID` & `AWS_SECRET_ACCESS_KEY`
4. **Permissions** — `AdministratorAccess` for training

</v-clicks>

<v-click>

<div class="mt-3 p-2 bg-red-50 text-gray-800 rounded-lg border-l-4 border-red-500 text-sm">
  ⚠️ <strong>Security:</strong> Never use root account credentials.
</div>

</v-click>

</div>
<div>

<v-click>

### IAM Policy (Best Practice)

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ec2:*", "s3:*",
      "dynamodb:*", "iam:*", "eks:*"
    ],
    "Resource": "*"
  }]
}
```

</v-click>

</div>
</div>

---

# Install Terraform

<div class="grid grid-cols-3 gap-3 pt-2">

<div class="p-3 bg-blue-50 text-gray-800 rounded-xl">

### 🐧 Linux

```bash
wget -O- https://apt.releases.\
hashicorp.com/gpg | sudo gpg \
--dearmor -o /usr/share/keyrings\
/hashicorp.gpg

sudo apt update
sudo apt install terraform
```

</div>

<div class="p-3 bg-green-50 text-gray-800 rounded-xl">

### 🍎 macOS

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

terraform -version
```

</div>

<div class="p-3 bg-purple-50 text-gray-800 rounded-xl">

### 🪟 Windows

```powershell
choco install terraform
# Or
scoop install terraform

terraform -version
```

</div>

</div>

<v-click>

<div class="mt-3 text-center p-2 bg-gray-50 text-gray-800 rounded-lg">

```bash
$ terraform -version
Terraform v1.9.x
```

</div>

</v-click>

---

# Introducing the Local Provider

<div class="grid grid-cols-2 gap-6">
<div>

### Why Start Local?

<v-clicks>

- No cloud account needed initially
- Instant feedback loop
- Learn HCL syntax safely
- Understand core concepts first

</v-clicks>

<v-click>

```hcl
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

resource "local_file" "hello" {
  content  = "Hello, Terraform!"
  filename = "${path.module}/hello.txt"
}
```

</v-click>

</div>
<div>

<v-click>

### Try It!

```bash
$ terraform init
Initializing provider plugins...
- Installing hashicorp/local v2.5.1...

$ terraform plan
+ local_file.hello will be created
Plan: 1 to add, 0 to change

$ terraform apply -auto-approve
Apply complete! Resources: 1 added

$ cat hello.txt
Hello, Terraform!
```

</v-click>

</div>
</div>

---

# Work Environment & Project Structure

<div class="grid grid-cols-2 gap-6">
<div>

### Required Tools

- **Terraform CLI** — Core tool
- **AWS CLI** — `aws configure`
- **VS Code** — HashiCorp Terraform extension
- **Git** — Version control

### VS Code Extensions

```
hashicorp.terraform    # Syntax, autocomplete
hashicorp.hcl          # HCL language support
```

</div>
<div>

### Recommended Structure

```
terraform-project/
├── main.tf           # Main resources
├── variables.tf      # Input variables
├── outputs.tf        # Output values
├── providers.tf      # Provider config
├── terraform.tfvars  # Variable values
├── versions.tf       # Version constraints
├── modules/
│   ├── vpc/
│   ├── ec2/
│   └── rds/
└── environments/
    ├── dev/
    ├── staging/
    └── prod/
```

</div>
</div>

---

# Terraform Providers

<div class="grid grid-cols-2 gap-6">
<div>

### What Are Providers?

<v-clicks>

- **Plugins** that let Terraform interact with APIs
- Each manages a set of **resource types**
- Published on the **Terraform Registry**
- Versioned independently from Terraform

</v-clicks>

<v-click>

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5.0"
}
```

</v-click>

</div>
<div>

<v-click>

### Popular Providers

| Provider | Resources |
|----------|-----------|
| **aws** | 1300+ types |
| **azurerm** | 900+ types |
| **google** | 700+ types |
| **kubernetes** | K8s resources |
| **docker** | Containers |

### Version Constraints

```hcl
version = "5.0.0"         # Exact
version = "~> 5.0"        # >= 5.0, < 6.0
version = ">= 5.0"        # 5.0 or higher
version = ">= 5.0, < 5.30"  # Range
```

</v-click>

</div>
</div>

---

# AWS Provider — Authentication Methods

<div class="grid grid-cols-2 gap-4">
<div>

### Method 1: Static Credentials ❌

```hcl
provider "aws" {
  region     = "us-east-1"
  access_key = "AKIAIOSFODNN7EXAMPLE"
  secret_key = "wJalrXUtnFEMI/..."
}
```

<div class="p-1 bg-red-50 text-gray-800 rounded border-l-4 border-red-500 text-xs">
  ❌ <strong>Never</strong> hardcode credentials!
</div>

### Method 2: Environment Variables ✅

```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="wJal..."
export AWS_DEFAULT_REGION="us-east-1"
```

</div>
<div>

### Method 3: Credentials File ✅

```bash
# ~/.aws/credentials
[default]
aws_access_key_id = AKIA...
aws_secret_access_key = wJal...
```

```hcl
provider "aws" {
  region  = "us-east-1"
  profile = "default"
}
```

### Method 4: IAM Instance Profile ✅✅

```hcl
provider "aws" {
  region = "us-east-1"
  # Auto-discovers from EC2 metadata
}
```

<div class="p-1 bg-green-50 text-gray-800 rounded border-l-4 border-green-500 text-xs">
  ✅ Best for production — no credentials in code
</div>

</div>
</div>

---

# Deploying Your First Server

```hcl
provider "aws" {
  region = "us-east-1"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "my_first_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  tags = {
    Name = "MyFirstTerraformServer"
    Env  = "training"
  }
}

output "server_ip" {
  value = aws_instance.my_first_server.public_ip
}
```

---

# Deploy a Web Server

<div class="grid grid-cols-2 gap-4">
<div>

### Security Group

```hcl
resource "aws_security_group" "web_sg" {
  name = "web-server-sg"
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
```

</div>
<div>

### EC2 with user_data

```hcl
resource "aws_instance" "web_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  vpc_security_group_ids = [
    aws_security_group.web_sg.id
  ]

  user_data = <<-EOF
    #!/bin/bash
    yum update -y && yum install -y httpd
    systemctl start httpd
    echo "<h1>Hello from Terraform!</h1>" \
      > /var/www/html/index.html
  EOF

  tags = { Name = "WebServer" }
}
```

</div>
</div>

<div class="mt-2 p-2 bg-green-50 text-gray-800 rounded-lg text-xs">
  <strong>user_data</strong> runs on first boot — perfect for bootstrapping software
</div>

---

# Deploy a Configurable Web Server

<div class="grid grid-cols-2 gap-4">
<div>

### Variables

```hcl
variable "server_port" {
  description = "Port for the web server"
  type        = number
  default     = 8080
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}
```

</div>
<div>

### Using Variables

```hcl
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  user_data = <<-EOF
    #!/bin/bash
    echo "<h1>Port ${var.server_port}!</h1>" \
      > index.html
    nohup python3 -m http.server \
      ${var.server_port} &
  EOF

  tags = {
    Name = "Web-${var.server_port}"
  }
}

output "url" {
  value = "http://${aws_instance.web.public_ip}:${var.server_port}"
}
```

</div>
</div>

---

# Working with Terraform State

<div class="grid grid-cols-2 gap-4">
<div>

### What is State?

<v-clicks>

- **JSON file** (`terraform.tfstate`) mapping resources to real-world objects
- Tracks metadata, dependencies, attributes
- **Single source of truth** for Terraform
- Contains **sensitive data** — treat as secret!

</v-clicks>

<v-click>

### State Commands

```bash
terraform state list
terraform state show aws_instance.web
terraform state mv \
  aws_instance.old aws_instance.new
terraform state rm aws_instance.orphan
```

</v-click>

</div>
<div>

<v-click>

### State File Structure

```json
{
  "version": 4,
  "terraform_version": "1.9.0",
  "resources": [{
    "mode": "managed",
    "type": "aws_instance",
    "name": "web",
    "instances": [{
      "attributes": {
        "id": "i-0abc123def456",
        "ami": "ami-0abcdef",
        "instance_type": "t2.micro",
        "public_ip": "54.1.2.3"
      }
    }]
  }]
}
```

</v-click>

</div>
</div>

---

# Handling Updates & Destroying Resources

<div class="grid grid-cols-2 gap-4">
<div>

### The Plan/Apply Cycle

```bash
$ terraform plan
~ aws_instance.web will be updated
  ~ instance_type: "t2.micro" -> "t2.small"
Plan: 0 to add, 1 to change, 0 to destroy

$ terraform apply
Apply complete! 0 added, 1 changed
```

### Update Types

| Change | Result |
|--------|--------|
| Tags | In-place update |
| Instance type | Stop → Update → Start |
| AMI | Destroy → Recreate |

</div>
<div>

### Destroying Resources

```bash
# Destroy everything
$ terraform destroy
Plan: 0 to add, 0 to change, 3 to destroy
Do you really want to destroy? (yes/no)

# Targeted destroy
$ terraform destroy -target=aws_instance.web

# Remove from Terraform's control only
$ terraform state rm aws_instance.web
```

<v-click>

<div class="mt-3 p-2 bg-red-50 text-gray-800 rounded-lg border-l-4 border-red-500 text-xs">
  ⚠️ <strong>Caution:</strong> <code>terraform destroy</code> permanently removes real infrastructure. Always review the plan!
</div>

</v-click>

</div>
</div>

---

# 🔬 Hands-On Lab: Full EC2 Lifecycle

<div class="p-5 bg-gradient-to-br from-blue-50 to-purple-50 rounded-xl">

### Lab Objectives

<v-clicks>

1. **Create** — Write Terraform config for EC2 + security group
2. **Initialize** — Run `terraform init` to download the AWS provider
3. **Plan** — Run `terraform plan` to preview the resources
4. **Apply** — Run `terraform apply` to create the infrastructure
5. **Verify** — Access the web server via its public IP
6. **Update** — Change instance type and re-apply
7. **Observe** — Note in-place vs. destructive updates
8. **Destroy** — Clean up with `terraform destroy`

</v-clicks>

</div>

<v-click>

<div class="mt-3 p-2 bg-yellow-50 text-gray-800 rounded-lg border-l-4 border-yellow-500">
  <strong>⏱ Estimated time:</strong> 30 minutes | <strong>Region:</strong> us-east-1
</div>

</v-click>

---
class: text-center flex flex-col items-center justify-center
---

# <span class="text-orange-600">Variables & Expressions</span>

<div class="pt-4">
  <span class="px-6 py-3 rounded-xl bg-gradient-to-r from-orange-500 to-amber-500 text-white text-xl font-bold shadow-lg">
    Making Terraform Configurations Dynamic
  </span>
</div>

---

# Input Variables

<div class="grid grid-cols-2 gap-4">
<div>

### Variable Declaration

```hcl
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_count" {
  type    = number
  default = 2
}

variable "enable_monitoring" {
  type    = bool
  default = false
}

variable "allowed_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/16"]
}
```

</div>
<div>

### Variable Types

```
string  → "hello"       list   → ["a","b"]
number  → 42             map    → {key="val"}
bool    → true/false     set    → toset(["a"])
object  → {name=string}  tuple  → [string,number]
```

### Using & Setting Variables

```hcl
resource "aws_instance" "web" {
  instance_type = var.instance_type
  tags = {
    Name = "web-${var.environment}"
  }
}
```

```bash
terraform apply -var="region=us-west-2"
terraform apply -var-file="prod.tfvars"
export TF_VAR_region="us-west-2"
```

</div>
</div>

---

# Output Values

<div class="grid grid-cols-2 gap-4">
<div>

### Defining Outputs

```hcl
output "instance_id" {
  description = "The EC2 instance ID"
  value       = aws_instance.web.id
}

output "public_ip" {
  value = aws_instance.web.public_ip
}

output "website_url" {
  value = "http://${aws_instance.web.public_ip}:${var.server_port}"
}

output "db_password" {
  value     = var.db_password
  sensitive = true
}
```

</div>
<div>

### Using Outputs

```bash
$ terraform output
instance_id = "i-0abc123def456"
public_ip   = "54.1.2.3"
website_url = "http://54.1.2.3:8080"
db_password = <sensitive>

$ terraform output public_ip
"54.1.2.3"

$ terraform output -raw public_ip
54.1.2.3

$ terraform output -json
```

<div class="mt-3 p-2 bg-blue-50 text-gray-800 rounded-lg border-l-4 border-blue-500 text-xs">
  <strong>Tip:</strong> Outputs share data between modules and remote state files.
</div>

</div>
</div>

---

# Local Values & Variable Validation

<div class="grid grid-cols-2 gap-4">
<div>

### Locals

```hcl
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
  name_prefix = "${var.project}-${var.env}"
}

resource "aws_instance" "web" {
  ami           = var.ami_id
  instance_type = var.instance_type
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-web"
  })
}
```

</div>
<div>

### Validation

```hcl
variable "environment" {
  type = string
  validation {
    condition = contains(
      ["dev", "staging", "prod"],
      var.environment
    )
    error_message = "Must be dev, staging, or prod."
  }
}
```

### Environment Variables

```bash
export TF_VAR_region="us-west-2"
export TF_VAR_instance_type="t3.medium"
export TF_VAR_db_password="s3cr3t"
```

</div>
</div>

---

# Variable Files (.tfvars)

<div class="grid grid-cols-2 gap-4">
<div>

### Per-Environment Files

```hcl
# dev.tfvars
environment    = "dev"
instance_type  = "t2.micro"
instance_count = 1
region         = "us-east-1"

# prod.tfvars
environment    = "prod"
instance_type  = "t3.large"
instance_count = 3
region         = "us-east-1"
```

```bash
# Auto-loaded files
terraform.tfvars
*.auto.tfvars

# Explicit file
terraform apply -var-file="prod.tfvars"
```

</div>
<div>

### Maps & Lists

```hcl
variable "ami_map" {
  type = map(string)
  default = {
    us-east-1 = "ami-0abcdef1234567890"
    us-west-2 = "ami-0fedcba9876543210"
  }
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

resource "aws_instance" "web" {
  ami               = var.ami_map[var.region]
  availability_zone = var.azs[0]
}
```

</div>
</div>

---

# Functions & Templates

<div class="grid grid-cols-2 gap-4">
<div>

### Built-in Functions

```hcl
# String
upper("hello")          # "HELLO"
join(", ", ["a", "b"])  # "a, b"
split(",", "a,b,c")    # ["a","b","c"]
format("Hi, %s!", "TF") # "Hi, TF!"

# Numeric
max(5, 12, 9)   # 12
min(5, 12, 9)   # 5
ceil(4.3)       # 5

# Collection
length(["a", "b"])     # 2
merge(map1, map2)      # Combined map
flatten([[1,2],[3]])   # [1,2,3]
lookup(map, key, def)  # Map lookup
contains(list, "x")   # bool
```

</div>
<div>

### templatefile()

```bash
# templates/user_data.sh
#!/bin/bash
echo "Setting up ${app_name}..."
yum update -y && yum install -y httpd
cat > /var/www/html/index.html <<HTML
<h1>Welcome to ${app_name}</h1>
<p>Port ${port} | Env: ${environment}</p>
HTML
systemctl start httpd
```

```hcl
resource "aws_instance" "web" {
  ami           = var.ami_id
  instance_type = var.instance_type
  user_data = templatefile(
    "templates/user_data.sh", {
      app_name    = var.app_name
      port        = var.server_port
      environment = var.environment
  })
}
```

</div>
</div>

---
class: text-center flex flex-col items-center justify-center
---

# <span class="text-purple-600">Resource Dependencies & Modules</span>

<div class="pt-4">
  <span class="px-6 py-3 rounded-xl bg-gradient-to-r from-purple-500 to-pink-500 text-white text-xl font-bold shadow-lg">
    Building Connected Infrastructure
  </span>
</div>

---

# Resource Dependencies

<div class="grid grid-cols-2 gap-4">
<div>

### Implicit Dependencies

```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "web" {
  vpc_id     = aws_vpc.main.id  # ← implicit
  cidr_block = "10.0.1.0/24"
}

resource "aws_instance" "web" {
  subnet_id     = aws_subnet.web.id
  ami           = var.ami_id
  instance_type = "t2.micro"
}
```

<div class="mt-1 p-1 bg-blue-50 text-gray-800 rounded text-xs">
  Terraform builds a <strong>dependency graph</strong> automatically.
</div>

</div>
<div>

### Explicit Dependencies

```hcl
resource "aws_s3_bucket" "logs" {
  bucket = "my-app-logs"
}

resource "aws_instance" "app" {
  ami           = var.ami_id
  instance_type = "t2.micro"
  depends_on = [aws_s3_bucket.logs]
}
```

### Dependency Graph

```bash
$ terraform graph | dot -Tpng > graph.png
```

```mermaid {scale: 0.45}
graph LR
    VPC --> Subnet --> Instance
    SG --> Instance
    style VPC fill:#3B82F6,color:#fff
    style Subnet fill:#8B5CF6,color:#fff
    style Instance fill:#10B981,color:#fff
    style SG fill:#F59E0B,color:#fff
```

</div>
</div>

---

# Lifecycle Rules & Modules Intro

<div class="grid grid-cols-2 gap-4">
<div>

### Lifecycle Rules

```hcl
resource "aws_instance" "web" {
  ami           = var.ami_id
  instance_type = "t2.micro"

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = true
    ignore_changes = [tags, user_data]
  }
}
```

</div>
<div>

### Modules Introduction

```hcl
module "web_server" {
  source        = "./modules/ec2"
  instance_type = "t2.micro"
  ami_id        = var.ami_id
  server_name   = "production-web"
}

output "web_ip" {
  value = module.web_server.public_ip
}
```

```
modules/ec2/
├── main.tf        # Resources
├── variables.tf   # Inputs
└── outputs.tf     # Outputs
```

<div class="mt-2 p-2 bg-purple-50 text-gray-800 rounded-lg border-l-4 border-purple-500 text-xs">
  <strong>Modules</strong> = Reusable, testable, composable infrastructure packages.
</div>

</div>
</div>

---
class: text-center flex flex-col items-center justify-center
---

# <span class="text-indigo-600">DAY 2</span>
## Terraform Language, Core Resources, State & Backend

<div class="pt-4">
  <span class="px-6 py-3 rounded-xl bg-gradient-to-r from-indigo-500 to-blue-500 text-white text-xl font-bold shadow-lg">
    Deep Dive into HCL, Resources & Remote State
  </span>
</div>

---

# Variable Precedence & Data Sources

<div class="grid grid-cols-2 gap-4">
<div>

### Variable Precedence (Low → High)

<v-clicks>

1. Default value in variable block
2. `terraform.tfvars` file
3. `*.auto.tfvars` files (alphabetical)
4. `-var-file` flag
5. `-var` flag
6. `TF_VAR_*` environment variables

</v-clicks>

<v-click>

<div class="mt-2 p-2 bg-yellow-50 text-gray-800 rounded text-xs">
  Last one wins! Environment variables override everything.
</div>

</v-click>

</div>
<div>

### Data Sources

```hcl
data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/*"]
  }
}

data "aws_caller_identity" "current" {}

resource "aws_instance" "web" {
  ami       = data.aws_ami.ubuntu.id
  subnet_id = tolist(
    data.aws_vpc.default.subnet_ids
  )[0]
}
```

</div>
</div>

---

# Resource Block Structure

<div class="grid grid-cols-2 gap-4">
<div>

### Syntax

```hcl
resource "TYPE" "NAME" {
  argument1 = value1

  nested_block {
    key = "value"
  }

  count      = 3
  depends_on = [aws_vpc.main]

  lifecycle {
    create_before_destroy = true
  }
  tags = { Name = "example" }
}
```

### CRUD Behavior

| Action | When |
|--------|------|
| **Create** | In config, not in state |
| **Read** | Every plan/apply |
| **Update** | Attribute changed |
| **Delete** | Removed from config |

</div>
<div>

### Real-World Example

```hcl
resource "aws_instance" "app" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer.key_name
  subnet_id     = aws_subnet.private[0].id
  vpc_security_group_ids = [
    aws_security_group.app.id
  ]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  user_data = templatefile("init.sh", {
    env = var.environment
  })

  tags = merge(local.common_tags, {
    Name = "${local.prefix}-app"
  })
}
```

</div>
</div>

---

# Meta-Arguments: count & for_each

<div class="grid grid-cols-2 gap-4">
<div>

### count — Index-Based

```hcl
resource "aws_instance" "web" {
  count         = var.server_count
  ami           = var.ami_id
  instance_type = "t2.micro"
  tags = {
    Name = "web-${count.index + 1}"
  }
}

# Access:
# aws_instance.web[0].id
# aws_instance.web[*].public_ip
```

<div class="mt-2 p-1 bg-yellow-50 text-gray-800 rounded text-xs">
  ⚠️ Removing item at index 0 recreates all!
</div>

</div>
<div>

### for_each — Key-Based ✅

```hcl
variable "servers" {
  default = {
    web   = "t2.micro"
    api   = "t2.small"
    admin = "t2.micro"
  }
}

resource "aws_instance" "app" {
  for_each      = var.servers
  ami           = var.ami_id
  instance_type = each.value
  tags = {
    Name = each.key
    Type = each.value
  }
}
# Access: aws_instance.app["web"].id
```

<div class="mt-2 p-1 bg-green-50 text-gray-800 rounded text-xs">
  ✅ Removing "api" only destroys that one instance.
</div>

</div>
</div>

---

# Provider Aliasing (Multi-Region)

```hcl
provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "west"
  region = "us-west-2"
}

provider "aws" {
  alias  = "eu"
  region = "eu-west-1"
}

resource "aws_instance" "us_east" {
  ami           = var.ami_east
  instance_type = "t2.micro"
}

resource "aws_instance" "us_west" {
  provider      = aws.west
  ami           = var.ami_west
  instance_type = "t2.micro"
}

resource "aws_instance" "europe" {
  provider      = aws.eu
  ami           = var.ami_eu
  instance_type = "t2.micro"
}
```

---

# Lifecycle — Full Options

```hcl
resource "aws_instance" "web" {
  ami           = var.ami_id
  instance_type = var.instance_type

  lifecycle {
    create_before_destroy = true       # Zero-downtime: new before old destroyed
    prevent_destroy       = true       # Prevent accidental deletion
    ignore_changes        = [tags, user_data]  # Ignore external changes

    replace_triggered_by = [           # Replace when AMI changes
      null_resource.ami_update.id
    ]

    precondition {
      condition     = var.instance_type != "t2.nano"
      error_message = "t2.nano is too small."
    }

    postcondition {
      condition     = self.public_ip != ""
      error_message = "No public IP assigned."
    }
  }
}
```

---

# Loops: for Expressions & Dynamic Blocks

<div class="grid grid-cols-2 gap-4">
<div>

### for Expressions

```hcl
locals {
  names = ["alice", "bob", "charlie"]
  upper_names = [
    for name in local.names : upper(name)
  ]
  # → ["ALICE", "BOB", "CHARLIE"]
}

locals {
  servers = {
    web  = { type = "t2.micro", env = "prod" }
    api  = { type = "t2.small", env = "prod" }
    test = { type = "t2.micro", env = "dev" }
  }
  prod_only = {
    for k, v in local.servers :
    k => v if v.env == "prod"
  }
}
```

</div>
<div>

### Dynamic Blocks

```hcl
resource "aws_security_group" "web" {
  name = "web-sg"

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ingress.value.cidrs
    }
  }
}
```

### Conditionals

```hcl
resource "aws_instance" "bastion" {
  count = var.create_bastion ? 1 : 0
  ami           = var.ami_id
  instance_type = "t2.micro"
}

locals {
  inst_type = var.environment == "prod" ? "t3.large" : "t2.micro"
}
```

</div>
</div>

---

# Zero-Downtime & Common Gotchas

<div class="grid grid-cols-2 gap-4">
<div>

### Zero-Downtime Pattern

```hcl
resource "aws_launch_template" "web" {
  image_id      = var.ami_id
  instance_type = var.instance_type
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web" {
  desired_capacity = 2
  max_size         = 4
  min_size         = 1
  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }
}
```

</div>
<div>

### Common Gotchas

**1. Count index shift**
```hcl
# Removing item 0 recreates 1,2,3...
# ✅ Use for_each instead
```

**2. Valid plan, failed apply**
```hcl
# AWS-side validation fails at apply
# ✅ Use unique names with random suffix
```

**3. Refactoring destroys resources**
```hcl
# Renaming recreates — use state mv
terraform state mv \
  aws_instance.old aws_instance.new
```

**4. Eventual consistency**
```hcl
# AWS API may not reflect changes yet
# ✅ Add depends_on for hidden deps
```

</div>
</div>

---
class: text-center flex flex-col items-center justify-center
---

# <span class="text-cyan-600">Containers & EKS</span>

<div class="pt-4">
  <span class="px-6 py-3 rounded-xl bg-gradient-to-r from-cyan-500 to-blue-500 text-white text-xl font-bold shadow-lg">
    Kubernetes on AWS with Terraform
  </span>
</div>

---

# EKS Cluster with Terraform

<div class="grid grid-cols-2 gap-4">
<div>

### IAM & Cluster

```hcl
resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role"
  assume_role_policy = data
    .aws_iam_policy_document
    .eks_assume.json
}

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.30"
  vpc_config {
    subnet_ids = aws_subnet.private[*].id
    endpoint_private_access = true
    endpoint_public_access  = true
  }
}
```

</div>
<div>

### Node Group

```hcl
resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "workers"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = aws_subnet.private[*].id

  scaling_config {
    desired_size = 2
    max_size     = 5
    min_size     = 1
  }
  instance_types = ["t3.medium"]
}
```

### K8s Resource Hierarchy

```
Pod → ReplicaSet → Deployment
         ↓
    Service (ClusterIP/NodePort/LB)
         ↓
    Ingress (ALB/NLB)
```

</div>
</div>

---

# ECR Repository

```hcl
resource "aws_ecr_repository" "app" {
  name                 = "my-app"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}
```

<div class="mt-2 p-2 bg-cyan-50 text-gray-800 rounded text-sm">
  Terraform manages the EKS cluster and ECR; the <strong>Kubernetes provider</strong> manages workloads (Pods, Deployments, Services).
</div>

---
class: text-center flex flex-col items-center justify-center
---

# <span class="text-red-600">Terraform State Management</span>

<div class="pt-4">
  <span class="px-6 py-3 rounded-xl bg-gradient-to-r from-red-500 to-pink-500 text-white text-xl font-bold shadow-lg">
    Remote State, Locking & Isolation
  </span>
</div>

---

# Remote State with S3 Backend

<div class="grid grid-cols-2 gap-4">
<div>

### Why Remote State?

<v-clicks>

- **Shared access** — Team sees same state
- **Locking** — Prevent concurrent modifications
- **Versioning** — Roll back if corrupted
- **Encryption** — State contains secrets!

</v-clicks>

<v-click>

### S3 Backend Config

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

</v-click>

</div>
<div>

<v-click>

### Bootstrap the Backend

```hcl
resource "aws_s3_bucket" "state" {
  bucket = "my-terraform-state"
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_dynamodb_table" "locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}
```

</v-click>

</div>
</div>

---

# State Isolation Strategies

<div class="grid grid-cols-2 gap-4">
<div>

### Workspaces

```bash
$ terraform workspace new dev
$ terraform workspace new staging
$ terraform workspace new prod
$ terraform workspace select prod
$ terraform workspace list
  default
  dev
  staging
* prod
```

```hcl
resource "aws_instance" "web" {
  instance_type = (
    terraform.workspace == "prod"
    ? "t3.large" : "t2.micro"
  )
}
```

<div class="p-1 bg-yellow-50 text-gray-800 rounded text-xs">
  ⚠️ Workspaces share backend config — only state key differs.
</div>

</div>
<div>

### File Layout Isolation ✅

```
infrastructure/
├── dev/
│   └── backend.tf → s3://state/dev/
├── staging/
│   └── backend.tf → s3://state/staging/
└── prod/
    └── backend.tf → s3://state/prod/
```

### Reading Remote State

```hcl
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "my-terraform-state"
    key    = "vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

resource "aws_instance" "web" {
  subnet_id = data.terraform_remote_state
    .vpc.outputs.subnet_id
}
```

</div>
</div>

---

# Importing Resources

<div class="grid grid-cols-2 gap-4">
<div>

### terraform import

```bash
$ terraform import \
    aws_instance.web \
    i-0abc123def456789

$ terraform import \
    aws_s3_bucket.data \
    my-existing-bucket
```

### Import Block (TF 1.5+)

```hcl
import {
  to = aws_instance.web
  id = "i-0abc123def456789"
}
```

```bash
$ terraform plan \
  -generate-config-out=generated.tf
```

</div>
<div>

### Provisioners (Last Resort)

```hcl
resource "aws_instance" "web" {
  ami           = var.ami_id
  instance_type = "t2.micro"

  provisioner "file" {
    source      = "scripts/setup.sh"
    destination = "/tmp/setup.sh"
  }

  provisioner "local-exec" {
    command = "echo ${self.public_ip} >> hosts.txt"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup.sh",
      "/tmp/setup.sh",
    ]
  }

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("~/.ssh/id_rsa")
    host        = self.public_ip
  }
}
```

</div>
</div>

---

# Ansible & null_resource

<div class="grid grid-cols-2 gap-4">
<div>

### Ansible via local-exec

```hcl
resource "aws_instance" "app" {
  ami           = var.ami_id
  instance_type = "t2.micro"
}

resource "null_resource" "ansible" {
  triggers = {
    instance_id = aws_instance.app.id
  }
  provisioner "local-exec" {
    command = <<-EOT
      ANSIBLE_HOST_KEY_CHECKING=False \
      ansible-playbook \
        -i '${aws_instance.app.public_ip},' \
        -u ec2-user \
        --private-key ~/.ssh/id_rsa \
        playbook.yml
    EOT
  }
}
```

</div>
<div>

### null_resource Patterns

```hcl
resource "null_resource" "deploy" {
  triggers = {
    app_version = var.app_version
    config_hash = md5(file("config.json"))
  }
  provisioner "local-exec" {
    command = "./scripts/deploy.sh ${var.app_version}"
  }
}

resource "null_resource" "cleanup" {
  provisioner "local-exec" {
    when    = destroy
    command = "./scripts/cleanup.sh"
  }
}
```

<div class="mt-2 p-2 bg-blue-50 text-gray-800 rounded-lg text-xs">
  Use <code>triggers</code> to re-run provisioners when values change.
</div>

</div>
</div>

---
class: text-center flex flex-col items-center justify-center
---

# <span class="text-emerald-600">DAY 3</span>
## Team Workflows, Modules, Functions, Scaling & AWS

<div class="pt-4">
  <span class="px-6 py-3 rounded-xl bg-gradient-to-r from-emerald-500 to-teal-500 text-white text-xl font-bold shadow-lg">
    Scaling Infrastructure & Team Collaboration
  </span>
</div>

---

# Team Workflow & Git Strategy

<div class="grid grid-cols-2 gap-4">
<div>

### Git Branching

```mermaid {scale: 0.5}
gitGraph
    commit id: "init"
    branch feature/add-vpc
    commit id: "vpc"
    commit id: "subnets"
    checkout main
    merge feature/add-vpc id: "PR #1"
    branch feature/add-eks
    commit id: "eks"
    checkout main
    merge feature/add-eks id: "PR #2"
```

### Workflow

1. Create feature branch
2. Write Terraform code
3. `terraform plan` → attach to PR
4. Code review by team
5. Merge to main
6. CI/CD runs `terraform apply`

</div>
<div>

### Coding Guidelines

```hcl
# ✅ snake_case naming
resource "aws_instance" "web_server" {}
variable "instance_type" {}

# ✅ Standard file layout
main.tf          # Resources
variables.tf     # Inputs
outputs.tf       # Outputs
providers.tf     # Providers
```

### CI/CD Pipeline

```yaml
# .github/workflows/terraform.yml
jobs:
  terraform:
    steps:
      - uses: hashicorp/setup-terraform@v3
      - run: terraform init
      - run: terraform validate
      - run: terraform plan -out=plan.tfplan
      - run: terraform apply plan.tfplan
        if: github.ref == 'refs/heads/main'
```

</div>
</div>

---

# Data Sources — Deep Dive

<div class="grid grid-cols-2 gap-4">
<div>

### Common Patterns

```hcl
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_vpc" "production" {
  tags = { Name = "production-vpc" }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.production.id]
  }
  tags = { Tier = "private" }
}
```

</div>
<div>

### External Data Source

```hcl
data "external" "git_info" {
  program = ["bash",
    "${path.module}/scripts/git-info.sh"
  ]
}

# scripts/git-info.sh outputs JSON:
# {"branch":"main","commit":"abc123"}

resource "aws_instance" "web" {
  ami           = var.ami_id
  instance_type = "t2.micro"
  tags = {
    GitBranch = data.external
      .git_info.result.branch
    GitCommit = data.external
      .git_info.result.commit
  }
}
```

<div class="mt-2 p-1 bg-yellow-50 text-gray-800 rounded text-xs">
  ⚠️ External data sources must output valid JSON to stdout.
</div>

</div>
</div>

---

# Terraform Functions Reference

<div class="grid grid-cols-3 gap-3 text-xs">

<div class="p-2 bg-blue-50 text-gray-800 rounded-xl">

### Numeric & String
```hcl
abs(-5)         # 5
ceil(4.3)       # 5
floor(4.9)      # 4
max(3, 7, 2)    # 7
min(3, 7, 2)    # 2
upper("hello")  # HELLO
lower("HELLO")  # hello
trim("  hi  ")  # "hi"
replace("hi","i","o") # "ho"
format("v%d", 1)      # "v1"
join(",", ["a","b"])   # "a,b"
split(",", "a,b")      # ["a","b"]
```

</div>

<div class="p-2 bg-green-50 text-gray-800 rounded-xl">

### Collection
```hcl
length([1,2,3])       # 3
concat([1],[2,3])     # [1,2,3]
flatten([[1],[2]])    # [1,2]
keys({a=1,b=2})      # ["a","b"]
values({a=1})        # [1]
merge(m1, m2)        # merged
lookup(m,"k","def")  # value
contains(l,"x")      # bool
distinct([1,1,2])    # [1,2]
sort(["c","a"])      # ["a","c"]
zipmap(keys,vals)    # map
```

</div>

<div class="p-2 bg-purple-50 text-gray-800 rounded-xl">

### Filesystem & Encoding
```hcl
file("path/to/file")
fileexists("path")
templatefile("t.sh",{p=8080})
abspath("./rel")
basename("/a/b.txt")

jsonencode({a = 1})
yamlencode({a = 1})
base64encode("hello")
urlencode("a b")

# Date, IP & Hash
timestamp()
formatdate("YYYY-MM-DD",t)
cidrsubnet("10.0.0.0/16",8,1)
md5("hello")
sha256("hello")
```

</div>

</div>

---

# Reusable Modules — Definition

<div class="grid grid-cols-2 gap-4">
<div>

### Module Structure

```
modules/web-server/
├── main.tf
├── variables.tf
└── outputs.tf
```

### Definition

```hcl
# variables.tf
variable "instance_type" {
  type    = string
  default = "t2.micro"
}
variable "server_name" { type = string }
variable "vpc_id"      { type = string }
variable "subnet_id"   { type = string }

# main.tf
resource "aws_security_group" "web" {
  vpc_id = var.vpc_id
  ingress {
    from_port = 80; to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.al2.id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id
  vpc_security_group_ids = [
    aws_security_group.web.id
  ]
  tags = { Name = var.server_name }
}
```

</div>
<div>

### Using Modules

```hcl
# Local path
module "web" {
  source        = "./modules/web-server"
  server_name   = "production-web"
  instance_type = "t3.medium"
  vpc_id        = aws_vpc.main.id
  subnet_id     = aws_subnet.public[0].id
}

# Terraform Registry
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"
  name    = "production"
  cidr    = "10.0.0.0/16"
  azs     = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24"]
  public_subnets  = ["10.0.101.0/24"]
}

# Git
module "app" {
  source = "git::https://github.com/org/modules.git//app?ref=v1.2.0"
}
```

### Versioning

```hcl
version = "~> 5.0"  # >= 5.0, < 6.0
```

</div>
</div>

---

# Scaling: Auto Scaling Group

```hcl
resource "aws_launch_template" "web" {
  name_prefix   = "web-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  network_interfaces {
    security_groups = [aws_security_group.web.id]
  }
  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "web-asg" }
  }
}

resource "aws_autoscaling_group" "web" {
  name                = "web-asg"
  desired_capacity    = 2
  max_size            = 10
  min_size            = 1
  vpc_zone_identifier = aws_subnet.private[*].id
  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }
}
```

---

# Application Load Balancer

```hcl
resource "aws_lb" "web" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "web" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_autoscaling_attachment" "web" {
  autoscaling_group_name = aws_autoscaling_group.web.id
  lb_target_group_arn    = aws_lb_target_group.web.arn
}
```

---

# Blue-Green & Rolling Deployments

<div class="grid grid-cols-2 gap-4">
<div>

### Blue-Green

```hcl
variable "active_color" { default = "blue" }

resource "aws_instance" "blue" {
  count         = 2
  ami           = var.blue_ami
  instance_type = "t3.medium"
  tags          = { Color = "blue" }
}

resource "aws_instance" "green" {
  count         = 2
  ami           = var.green_ami
  instance_type = "t3.medium"
  tags          = { Color = "green" }
}

resource "aws_lb_target_group_attachment" "active" {
  count            = 2
  target_group_arn = aws_lb_target_group.web.arn
  target_id = (
    var.active_color == "blue"
    ? aws_instance.blue[count.index].id
    : aws_instance.green[count.index].id
  )
}
```

</div>
<div>

### Rolling AMI Upgrade

```hcl
resource "aws_launch_template" "app" {
  image_id      = var.ami_id
  instance_type = var.instance_type
}

resource "aws_autoscaling_group" "app" {
  desired_capacity = 4
  max_size         = 8
  min_size         = 2
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 75
      instance_warmup        = 120
    }
    triggers = ["launch_template"]
  }
}
```

<div class="mt-2 p-1 bg-green-50 text-gray-800 rounded border-l-4 border-green-500 text-xs">
  ✅ Change <code>var.ami_id</code> → ASG replaces 25% at a time.
</div>

</div>
</div>

---

# Collaborative Infrastructure

<div class="grid grid-cols-2 gap-4">
<div>

### Git for Terraform

```bash
# .gitignore
*.tfstate
*.tfstate.*
*.tfvars     # May contain secrets
.terraform/
crash.log
```

### Protecting Secrets

```hcl
provider "aws" {
  region = var.region
  # Creds from env: AWS_ACCESS_KEY_ID
}

data "aws_secretsmanager_secret_version" "db" {
  secret_id = "prod/db/password"
}

resource "aws_db_instance" "main" {
  password = data
    .aws_secretsmanager_secret_version
    .db.secret_string
}
```

</div>
<div>

### Terragrunt — DRY Terraform

```hcl
# terragrunt.hcl (root)
remote_state {
  backend = "s3"
  config = {
    bucket = "my-tf-state"
    key    = "${path_relative_to_include()}/terraform.tfstate"
    region = "us-east-1"
  }
}

# environments/prod/app/terragrunt.hcl
include "root" {
  path = find_in_parent_folders()
}
terraform {
  source = "../../../modules/app"
}
dependency "vpc" {
  config_path = "../vpc"
}
inputs = {
  environment = "prod"
  vpc_id      = dependency.vpc.outputs.vpc_id
}
```

</div>
</div>

---
class: text-center flex flex-col items-center justify-center
---

# <span class="text-rose-600">DAY 4</span>
## Production-Grade Terraform, Security, Testing & Cloud

<div class="pt-4">
  <span class="px-6 py-3 rounded-xl bg-gradient-to-r from-rose-500 to-red-500 text-white text-xl font-bold shadow-lg">
    Enterprise Patterns, Security & Terraform Cloud
  </span>
</div>

---

# Production-Grade Terraform

<div class="grid grid-cols-2 gap-4">
<div>

### Production Checklist

<v-clicks>

- ✅ Remote state with locking & encryption
- ✅ Version pinning for providers & modules
- ✅ Environment isolation (dev/staging/prod)
- ✅ Least-privilege IAM for Terraform
- ✅ Code review via PR workflow
- ✅ CI/CD pipeline for plan & apply
- ✅ Automated testing (validate, plan, test)
- ✅ Monitoring for drift detection
- ✅ Tagging strategy for cost tracking

</v-clicks>

</div>
<div>

### Module Design

```
Single Responsibility
├── modules/networking/  # VPC, subnets
├── modules/compute/     # EC2, ASG, ALB
├── modules/database/    # RDS, ElastiCache
├── modules/security/    # IAM, SGs, KMS
└── modules/monitoring/  # CloudWatch, SNS

Composable Architecture
├── modules/base/        # Foundation
├── modules/app/         # App layer
└── environments/
    ├── dev/
    ├── staging/
    └── prod/
```

<div class="mt-2 p-1 bg-blue-50 text-gray-800 rounded text-xs">
  If a module takes more than 5 minutes to understand, it's too big.
</div>

</div>
</div>

---

# Terraform Use Cases & Ecosystem

<div class="grid grid-cols-3 gap-3 text-xs">

<div class="p-3 bg-blue-50 text-gray-800 rounded-xl">

### IaC Migration

```hcl
# CloudFormation → Terraform
import {
  to = aws_instance.legacy
  id = "i-0abc123"
}

terraform plan \
  -generate-config-out=imported.tf

terraform plan  # validate
```

</div>

<div class="p-3 bg-green-50 text-gray-800 rounded-xl">

### Immutable Infra

```hcl
# Packer → Terraform workflow
# 1. packer build app.pkr.hcl
# 2. Deploy with Terraform:
variable "ami_id" {
  description = "Packer-built AMI"
}
resource "aws_launch_template" "app" {
  image_id = var.ami_id
  lifecycle {
    create_before_destroy = true
  }
}
```

</div>

<div class="p-3 bg-purple-50 text-gray-800 rounded-xl">

### Tooling Ecosystem

| Tool | Purpose |
|------|---------|
| **Terragrunt** | DRY configs |
| **Atlantis** | PR automation |
| **tfenv** | Version mgmt |
| **tflint** | Linting |
| **tfsec** | Security scan |
| **Checkov** | Compliance |
| **Infracost** | Cost estimates |
| **pre-commit** | Git hooks |

</div>

</div>

---

# Security — Secrets Management

<div class="grid grid-cols-2 gap-4">
<div>

### Managing Secrets

```hcl
# ❌ Never do this
variable "db_password" {
  default = "mysecretpassword"
}

# ✅ Use sensitive flag
variable "db_password" {
  type      = string
  sensitive = true
}

# ✅ AWS Secrets Manager
data "aws_secretsmanager_secret_version" "db" {
  secret_id = "prod/db/credentials"
}

locals {
  db_creds = jsondecode(
    data.aws_secretsmanager_secret_version
      .db.secret_string
  )
}

# ✅ AWS SSM Parameter Store
data "aws_ssm_parameter" "api_key" {
  name            = "/app/prod/api_key"
  with_decryption = true
}
```

</div>
<div>

### Least-Privilege IAM

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformStateAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::tf-state/*"
    },
    {
      "Sid": "StateLocking",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource":
        "arn:aws:dynamodb:*:*:table/tf-locks"
    }
  ]
}
```

</div>
</div>

---

# Security — Provisioner Dangers & Encryption

<div class="grid grid-cols-2 gap-4">
<div>

### local-exec Dangers

```hcl
# ❌ DANGEROUS: Shell injection!
resource "null_resource" "bad" {
  provisioner "local-exec" {
    command = "echo ${var.user_input}"
  }
}

# ✅ SAFE: Use environment variables
resource "null_resource" "safe" {
  provisioner "local-exec" {
    command = "echo $USER_INPUT"
    environment = {
      USER_INPUT = var.user_input
    }
  }
}
```

</div>
<div>

### Encryption at Rest

```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
  }
}

resource "aws_kms_key" "state" {
  description         = "TF state encryption"
  enable_key_rotation = true
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

</div>
</div>

---

# Testing — terraform test

```hcl
# tests/ec2_test.tftest.hcl
variables {
  instance_type = "t2.micro"
  environment   = "test"
}

run "plan_creates_instance" {
  command = plan
  assert {
    condition     = aws_instance.web.instance_type == "t2.micro"
    error_message = "Wrong instance type"
  }
  assert {
    condition     = aws_instance.web.tags["Env"] == "test"
    error_message = "Missing environment tag"
  }
}

run "apply_creates_instance" {
  command = apply
  assert {
    condition     = output.public_ip != ""
    error_message = "No public IP assigned"
  }
}
```

```bash
$ terraform test
tests/ec2_test.tftest.hcl... pass
  run "plan_creates_instance"... pass
  run "apply_creates_instance"... pass
```

---

# Testing — Terratest & Compliance

<div class="grid grid-cols-2 gap-4">
<div>

### Terratest (Go)

```go
func TestWebServer(t *testing.T) {
    opts := &terraform.Options{
        TerraformDir: "../examples/web",
        Vars: map[string]interface{}{
            "instance_type": "t2.micro",
        },
    }
    defer terraform.Destroy(t, opts)
    terraform.InitAndApply(t, opts)

    ip := terraform.Output(t, opts, "public_ip")
    assert.NotEmpty(t, ip)

    url := "http://" + ip + ":8080"
    http_helper.HttpGetWithRetry(t,
        url, nil, 200,
        "Hello", 10, 5*time.Second)
}
```

</div>
<div>

### Compliance Testing

```bash
# tfsec — security scanner
$ tfsec .
Result: 2 passed, 0 warnings, 0 failures

# checkov — policy-as-code
$ checkov -d .
Passed: 15, Failed: 0, Skipped: 0
```

### Testing Pyramid

| Level | Tool | Speed |
|-------|------|-------|
| **Static** | `terraform validate`, tflint | Fast |
| **Unit** | `terraform test` | Fast |
| **Integration** | Terratest | Slow |
| **Compliance** | tfsec, Checkov | Fast |
| **E2E** | Full provision + verify | Slowest |

</div>
</div>

---

# Terraform Cloud & Enterprise

<div class="grid grid-cols-2 gap-4">
<div>

### Cloud Features

<v-clicks>

- **Remote execution** — Runs in TFC
- **VCS integration** — Auto plan/apply
- **Private registry** — Internal modules
- **Policy as code** — Sentinel/OPA
- **Cost estimation** — Before apply
- **Audit logging** — Full trail
- **SSO/RBAC** — Enterprise access

</v-clicks>

<v-click>

```hcl
terraform {
  cloud {
    organization = "my-company"
    workspaces {
      name = "production-infra"
    }
  }
}
```

</v-click>

</div>
<div>

### Sentinel Policy

```python
import "tfplan/v2" as tfplan

approved_types = [
    "t3.micro", "t3.small",
    "t3.medium", "t3.large",
]

ec2_instances = filter tfplan.resource_changes
    as _, rc {
    rc.type is "aws_instance" and
    rc.mode is "managed" and
    (rc.change.actions contains "create" or
     rc.change.actions contains "update")
}

instance_type_allowed = rule {
    all ec2_instances as _, inst {
        inst.change.after.instance_type
            in approved_types
    }
}

main = rule { instance_type_allowed }
```

<div class="mt-2 p-1 bg-blue-50 text-gray-800 rounded text-xs">
  Sentinel runs <strong>after plan, before apply</strong>.
</div>

</div>
</div>

---

# GitOps & Policy as Code

<div class="grid grid-cols-2 gap-4">
<div>

### GitOps Model

```mermaid {scale: 0.45}
graph TD
    A["Dev Push"] --> B["CI: plan"]
    B --> C{"PR Review"}
    C -->|Approved| D["Merge"]
    C -->|Rejected| A
    D --> E["CD: apply"]
    E --> F["AWS Infra"]
    F --> G["Drift Check"]
    G -->|Drift| H["Auto PR"]
    H --> A
    style A fill:#3B82F6,color:#fff
    style B fill:#F59E0B,color:#fff
    style C fill:#8B5CF6,color:#fff
    style D fill:#10B981,color:#fff
    style E fill:#EC4899,color:#fff
    style F fill:#06B6D4,color:#fff
```

</div>
<div>

### OPA (Open Policy Agent)

```hcl
package terraform.rules

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_instance"
    not resource.change.after.tags.Owner
    msg := sprintf(
        "'%s' missing 'Owner' tag",
        [resource.name]
    )
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_instance"
    not resource.change.after.tags.CostCenter
    msg := sprintf(
        "'%s' missing 'CostCenter' tag",
        [resource.name]
    )
}
```

```bash
$ terraform show -json plan.tfplan > plan.json
$ opa eval -d policy/ -i plan.json \
    "data.terraform.rules.deny"
```

</div>
</div>

---
class: text-center flex flex-col items-center justify-center
---

# <span class="text-amber-600">Hands-On PoC / Project</span>

<div class="pt-4">
  <span class="px-6 py-3 rounded-xl bg-gradient-to-r from-amber-500 to-orange-500 text-white text-xl font-bold shadow-lg">
    Capstone: End-to-End Production Deployment
  </span>
</div>

---

# Capstone: Full EKS Deployment

<div class="grid grid-cols-2 gap-4">
<div>

### Architecture

```mermaid {scale: 0.45}
graph TD
    subgraph VPC["VPC 10.0.0.0/16"]
        subgraph Pub["Public Subnets"]
            ALB["ALB"]
            NAT["NAT GW"]
        end
        subgraph Priv["Private Subnets"]
            EKS["EKS"]
            NG["Nodes ×3"]
            RDS["RDS"]
        end
    end
    Internet --> ALB --> NG
    NG --> EKS
    NG --> RDS
    Priv --> NAT --> Internet
    style VPC fill:#EFF6FF,stroke:#3B82F6
    style Pub fill:#ECFDF5,stroke:#10B981
    style Priv fill:#FEF3C7,stroke:#F59E0B
```

</div>
<div>

### Project Structure

```
capstone/
├── modules/
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── eks/
│   ├── rds/
│   └── alb/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   └── prod/
├── policies/
│   └── tags.rego
├── tests/
│   └── infra_test.tftest.hcl
└── .github/
    └── workflows/terraform.yml
```

</div>
</div>

---

# Capstone: VPC & EKS Module

<div class="grid grid-cols-2 gap-4">
<div>

### VPC Module

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"

  name = "prod-vpc"
  cidr = "10.0.0.0/16"

  azs = ["us-east-1a", "us-east-1b",
         "us-east-1c"]
  private_subnets = ["10.0.1.0/24",
    "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets = ["10.0.101.0/24",
    "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  enable_dns_hostnames = true
}
```

</div>
<div>

### EKS Module

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.0"

  cluster_name    = "prod-cluster"
  cluster_version = "1.30"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  eks_managed_node_groups = {
    general = {
      desired_size   = 3
      min_size       = 2
      max_size       = 10
      instance_types = ["t3.medium"]
    }
  }
}
```

</div>
</div>

---

# Capstone: CI/CD Pipeline

<div class="grid grid-cols-2 gap-4">
<div>

### GitHub Actions

```yaml
name: Terraform CI/CD
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1
      - run: terraform init
      - run: terraform validate
      - run: terraform plan -out=plan.tfplan
      - run: |
          pip install checkov
          checkov -d . --framework terraform
      - run: terraform apply plan.tfplan
        if: github.ref == 'refs/heads/main'
```

</div>
<div>

### State Operations

```bash
# List resources
$ terraform state list

# Move/rename
$ terraform state mv \
    aws_instance.web \
    aws_instance.web_server

# Remove from state (keep in cloud)
$ terraform state rm aws_instance.legacy

# Pull/push state
$ terraform state pull > state.json
$ terraform state push state.json

# Import unmanaged resource
$ terraform import \
    aws_instance.existing \
    i-0abc123def456
```

### Custom Providers

```
Built with Go using
terraform-plugin-sdk/v2

Implement CRUD methods:
Create, Read, Update, Delete
```

</div>
</div>

---
transition: fade
layout: center
class: text-center
---

# 🎓 Training Summary

<div class="grid grid-cols-4 gap-4 pt-6 text-sm">

<div class="p-4 bg-blue-50 text-gray-800 rounded-xl border-2 border-blue-200">
  <div class="text-3xl mb-2">📘</div>
  <h3 class="text-blue-700 font-bold">Day 1</h3>
  <p>IaC Foundations</p>
  <p>Variables & EC2</p>
  <p>First Deployment</p>
</div>

<div class="p-4 bg-green-50 text-gray-800 rounded-xl border-2 border-green-200">
  <div class="text-3xl mb-2">📗</div>
  <h3 class="text-green-700 font-bold">Day 2</h3>
  <p>HCL Deep Dive</p>
  <p>State & Backend</p>
  <p>EKS & Containers</p>
</div>

<div class="p-4 bg-purple-50 text-gray-800 rounded-xl border-2 border-purple-200">
  <div class="text-3xl mb-2">📙</div>
  <h3 class="text-purple-700 font-bold">Day 3</h3>
  <p>Team Workflows</p>
  <p>Modules & Scaling</p>
  <p>AWS Integration</p>
</div>

<div class="p-4 bg-red-50 text-gray-800 rounded-xl border-2 border-red-200">
  <div class="text-3xl mb-2">📕</div>
  <h3 class="text-red-700 font-bold">Day 4</h3>
  <p>Production Grade</p>
  <p>Security & Testing</p>
  <p>Terraform Cloud</p>
</div>

</div>

<div class="mt-6">
  <span class="px-6 py-3 rounded-xl bg-gradient-to-r from-blue-500 via-purple-500 to-pink-500 text-white text-lg font-bold shadow-lg">
    Thank You! Happy Terraforming! 🚀
  </span>
</div>

---
layout: end
---

# Resources & Next Steps

- **Terraform Docs** — developer.hashicorp.com/terraform
- **AWS Provider** — registry.terraform.io/providers/hashicorp/aws
- **Terraform Registry** — registry.terraform.io
- **Terratest** — github.com/gruntwork-io/terratest
- **"Terraform: Up & Running"** by Yevgeniy Brikman
