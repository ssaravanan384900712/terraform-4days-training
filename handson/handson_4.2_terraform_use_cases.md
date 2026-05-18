# Hands-On 4.2 — Terraform Use Cases and Tooling Ecosystem

**File:** `~/lab4.2-use-cases/`

---

## Concept

Terraform does not exist in isolation. Real-world teams combine it with configuration management tools (Ansible), image builders (Packer), CI/CD systems (Jenkins, GitHub Actions), and a rich ecosystem of helper tools. This lab walks through the most common integration patterns and gives you hands-on experience with the tooling that makes Terraform production-ready.

### Integration Landscape

```
  +------------------------------------------------------------------+
  |                        Developer Workflow                         |
  +------------------------------------------------------------------+
        |              |              |               |
        v              v              v               v
  +-----------+  +-----------+  +-----------+  +--------------+
  | tfenv     |  | pre-commit|  | atlantis  |  | terragrunt   |
  | (version  |  | (lint +   |  | (PR-based |  | (DRY config  |
  |  manager) |  |  format)  |  |  apply)   |  |  wrapper)    |
  +-----------+  +-----------+  +-----------+  +--------------+
        |              |              |               |
        v              v              v               v
  +------------------------------------------------------------------+
  |                     Terraform Core                                |
  +------------------------------------------------------------------+
        |              |              |               |
        v              v              v               v
  +-----------+  +-----------+  +-----------+  +--------------+
  |  Packer   |  |  Ansible  |  |  Jenkins  |  |  Terraform   |
  | (immutable|  | (config   |  | (CI/CD    |  |  Cloud       |
  |  images)  |  |  mgmt)    |  |  pipeline)|  |  (remote)    |
  +-----------+  +-----------+  +-----------+  +--------------+
```

---

## Part 1 — IaC Replacements: Migrating to Terraform

### Migrating from CloudFormation

When you have existing CloudFormation-managed resources, Terraform can take over using `terraform import`.

### Step 1: Discover existing resources

```bash
# List CloudFormation stacks
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE

# Get specific resource details
aws cloudformation describe-stack-resources \
  --stack-name my-legacy-stack \
  --query 'StackResources[].{Type:ResourceType,Physical:PhysicalResourceId}'
```

### Step 2: Write the Terraform equivalent

```hcl
# main.tf -- Terraform config matching the existing CFN resources

resource "aws_vpc" "imported" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "legacy-cfn-vpc"
  }
}
```

### Step 3: Import the resource

```bash
mkdir -p ~/lab4.2-use-cases/import-demo && cd ~/lab4.2-use-cases/import-demo

terraform init

# Import the existing VPC into Terraform state
terraform import aws_vpc.imported vpc-0abc123def456789

# Verify the import
terraform plan
# Expected: No changes. Infrastructure is up-to-date.
```

### Terraform 1.5+ Import Blocks (Declarative)

```hcl
# import.tf -- Declarative import (preferred in Terraform 1.5+)

import {
  to = aws_vpc.imported
  id = "vpc-0abc123def456789"
}

import {
  to = aws_subnet.public
  id = "subnet-0abc123def456789"
}
```

```bash
# Generate config from existing resources
terraform plan -generate-config-out=generated.tf

# Review generated.tf, then apply
terraform apply
```

### Migration Comparison

| Aspect | CloudFormation | CDK | Terraform |
|--------|---------------|-----|-----------|
| Language | YAML/JSON | TypeScript/Python | HCL |
| Multi-cloud | AWS only | AWS only | Any provider |
| State | Managed by AWS | Managed by AWS | Self-managed (or TFC) |
| Import | Drift detection | Via CFN | `terraform import` |
| Modularity | Nested stacks | Constructs | Modules |

---

## Part 2 — Terraform + Ansible (Provisioning + Configuration)

### The Pattern

```
  Terraform                          Ansible
  (Infrastructure)                   (Configuration)
  +------------------+               +------------------+
  | Create EC2       |  inventory    | Install packages |
  | Create VPC       |  ----------> | Configure nginx  |
  | Create SG        |  (dynamic)   | Deploy app code  |
  | Output: IP, key  |               | Manage services  |
  +------------------+               +------------------+
```

### Step 4: Terraform provisions, Ansible configures

```bash
mkdir -p ~/lab4.2-use-cases/terraform-ansible && cd ~/lab4.2-use-cases/terraform-ansible
```

```hcl
# main.tf

provider "aws" {
  region = "us-east-1"
}

resource "tls_private_key" "deploy" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "deploy" {
  key_name   = "ansible-deploy-key"
  public_key = tls_private_key.deploy.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.deploy.private_key_pem
  filename        = "${path.module}/deploy-key.pem"
  file_permission = "0600"
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.deploy.key_name
  vpc_security_group_ids = [aws_security_group.ssh_http.id]

  tags = { Name = "ansible-target" }
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_security_group" "ssh_http" {
  name_prefix = "ansible-target-"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

# --- Generate Ansible inventory dynamically ---
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tftpl", {
    web_ip      = aws_instance.web.public_ip
    private_key = "${path.module}/deploy-key.pem"
  })
  filename = "${path.module}/inventory.ini"
}

output "web_public_ip" {
  value = aws_instance.web.public_ip
}
```

```ini
# inventory.tftpl -- Ansible inventory template

[webservers]
${web_ip} ansible_user=ec2-user ansible_ssh_private_key_file=${private_key}

[webservers:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

```yaml
# playbook.yml -- Ansible playbook for web server config

---
- hosts: webservers
  become: true
  tasks:
    - name: Install httpd
      yum:
        name: httpd
        state: present

    - name: Start and enable httpd
      systemd:
        name: httpd
        state: started
        enabled: true

    - name: Deploy index page
      copy:
        content: "<h1>Configured by Ansible via Terraform</h1>"
        dest: /var/www/html/index.html
```

```bash
# Run the full workflow
terraform init && terraform apply -auto-approve

# Wait for instance to boot, then run Ansible
sleep 60
ansible-playbook -i inventory.ini playbook.yml

# Verify
curl http://$(terraform output -raw web_public_ip)
# Output: <h1>Configured by Ansible via Terraform</h1>
```

---

## Part 3 — Immutable Infrastructure with Packer

### The Immutable Pattern

```
  Build Phase                         Deploy Phase
  +------------------+               +------------------+
  | Packer template  |               | Terraform config |
  |   - base AMI     |  AMI ID       |   - Launch from  |
  |   - install deps |  ----------> |     custom AMI   |
  |   - configure    |               |   - No SSH after |
  |   - harden       |               |   - Replace, not |
  +------------------+               |     update       |
                                      +------------------+

  Mutable (Ansible):    Server v1 --> patch --> Server v1.1 --> patch --> ...
  Immutable (Packer):   AMI v1 --> new AMI v2 --> replace server entirely
```

### Packer template

```hcl
# web-server.pkr.hcl

packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "web" {
  ami_name      = "web-server-{{timestamp}}"
  instance_type = "t3.micro"
  region        = "us-east-1"

  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-x86_64"
      virtualization-type = "hvm"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  ssh_username = "ec2-user"
}

build {
  sources = ["source.amazon-ebs.web"]

  provisioner "shell" {
    inline = [
      "sudo yum update -y",
      "sudo yum install -y httpd",
      "sudo systemctl enable httpd",
      "echo '<h1>Immutable Web Server</h1>' | sudo tee /var/www/html/index.html"
    ]
  }
}
```

```bash
# Build the AMI
packer build web-server.pkr.hcl
# => ami-0xxxxxxxxxxxx

# Use in Terraform
# variable "ami_id" { default = "ami-0xxxxxxxxxxxx" }
```

---

## Part 4 — CI/CD with Jenkins

### Jenkinsfile for Terraform

```groovy
// Jenkinsfile

pipeline {
    agent any

    environment {
        TF_IN_AUTOMATION = 'true'
        AWS_REGION       = 'us-east-1'
    }

    parameters {
        choice(
            name: 'ACTION',
            choices: ['plan', 'apply', 'destroy'],
            description: 'Terraform action to perform'
        )
        choice(
            name: 'ENVIRONMENT',
            choices: ['dev', 'staging', 'prod'],
            description: 'Target environment'
        )
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Terraform Init') {
            steps {
                dir("environments/${params.ENVIRONMENT}") {
                    sh 'terraform init -input=false'
                }
            }
        }

        stage('Terraform Validate') {
            steps {
                dir("environments/${params.ENVIRONMENT}") {
                    sh 'terraform validate'
                    sh 'terraform fmt -check -recursive'
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                dir("environments/${params.ENVIRONMENT}") {
                    sh 'terraform plan -out=tfplan -input=false'
                }
            }
        }

        stage('Manual Approval') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                input message: "Apply plan to ${params.ENVIRONMENT}?"
            }
        }

        stage('Terraform Apply') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                dir("environments/${params.ENVIRONMENT}") {
                    sh 'terraform apply -auto-approve tfplan'
                }
            }
        }

        stage('Terraform Destroy') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                dir("environments/${params.ENVIRONMENT}") {
                    sh 'terraform destroy -auto-approve'
                }
            }
        }
    }

    post {
        always {
            dir("environments/${params.ENVIRONMENT}") {
                sh 'rm -f tfplan'
            }
        }
        failure {
            echo "Terraform ${params.ACTION} failed for ${params.ENVIRONMENT}"
        }
    }
}
```

---

## Part 5 — Tooling Ecosystem (Hands-On)

### Tool 1: tfenv (Terraform Version Manager)

```bash
# Install tfenv
git clone https://github.com/tfutils/tfenv.git ~/.tfenv
echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# List available versions
tfenv list-remote | head -10

# Install a specific version
tfenv install 1.7.5
tfenv install 1.8.0

# Switch versions
tfenv use 1.7.5
terraform version
# Terraform v1.7.5

tfenv use 1.8.0
terraform version
# Terraform v1.8.0

# Pin version per project (committed to repo)
echo "1.8.0" > .terraform-version
tfenv use    # reads .terraform-version automatically
```

### Tool 2: pre-commit hooks

```bash
mkdir -p ~/lab4.2-use-cases/pre-commit-demo && cd ~/lab4.2-use-cases/pre-commit-demo
git init

# Install pre-commit
pip install pre-commit
```

Create the configuration file:

```yaml
# .pre-commit-config.yaml

repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.96.1
    hooks:
      - id: terraform_fmt
        name: Terraform Format
        description: Rewrites Terraform files to canonical format.

      - id: terraform_validate
        name: Terraform Validate
        description: Validates Terraform configuration.

      - id: terraform_tflint
        name: TFLint
        description: Lints Terraform files.

      - id: terraform_docs
        name: Terraform Docs
        description: Generates documentation from Terraform modules.

      - id: terraform_tfsec
        name: TFSec
        description: Static analysis for Terraform security issues.

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-merge-conflict
```

```bash
# Install the hooks
pre-commit install

# Run against all files
pre-commit run --all-files
```

Expected output:
```
Terraform Format........................................................Passed
Terraform Validate......................................................Passed
TFLint..................................................................Passed
Terraform Docs..........................................................Passed
TFSec...................................................................Passed
Trim Trailing Whitespace................................................Passed
Fix End of Files........................................................Passed
Check for merge conflicts...............................................Passed
```

### Tool 3: Atlantis (PR-Based Terraform)

```
  Developer           GitHub            Atlantis           AWS
  +--------+        +--------+        +----------+      +-----+
  |  git   | push   | PR     | webhook| terraform|      |     |
  |  push  |------->| opened |------->| plan     |----->| API |
  +--------+        +--------+        +----------+      +-----+
                         |                  |
                         | comment:         |
                         | "atlantis apply" |
                         +-------+----------+
                                 |
                                 v
                          +----------+
                          | terraform|
                          | apply    |
                          +----------+
```

```yaml
# atlantis.yaml (repo-level config)
version: 3
projects:
  - name: dev
    dir: environments/dev
    workspace: default
    autoplan:
      when_modified:
        - "*.tf"
        - "../../modules/**/*.tf"
      enabled: true
  - name: prod
    dir: environments/prod
    workspace: default
    apply_requirements:
      - approved
      - mergeable
```

### Tool 4: Terragrunt (Quick Reference)

```bash
# Install Terragrunt
brew install terragrunt   # macOS
# or download from https://terragrunt.gruntwork.io/

# Run across all modules in an environment
cd live/dev
terragrunt run-all plan
terragrunt run-all apply

# Dependency graph
terragrunt graph-dependencies
```

---

## Part 6 — Terraform Cloud Overview

### Workspace Types

| Feature | CLI-Driven | VCS-Driven |
|---------|-----------|------------|
| Trigger | `terraform plan` from CLI | Git push / PR |
| Config source | Local files | VCS repo |
| Best for | Local dev, migration | Full CI/CD |
| Speculative plans | Yes | Yes (on PRs) |

### Cloud Backend Block

```hcl
# main.tf -- Connect to Terraform Cloud

terraform {
  cloud {
    organization = "my-org"

    workspaces {
      name = "my-app-dev"
    }
  }
}
```

```bash
# Login to Terraform Cloud
terraform login

# Initialize with cloud backend
terraform init

# Run remotely
terraform plan   # Executes in TFC, streams output locally
terraform apply  # Executes in TFC
```

---

## Part 7 — Hands-On: terraform import

### Step 5: Import an existing S3 bucket

```bash
mkdir -p ~/lab4.2-use-cases/import-lab && cd ~/lab4.2-use-cases/import-lab
```

```bash
# Create a bucket outside of Terraform (simulating pre-existing resource)
aws s3 mb s3://lab42-import-demo-$(date +%s) --region us-east-1
# Note the bucket name from output
```

```hcl
# main.tf

terraform {
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

# Write config matching the existing bucket
resource "aws_s3_bucket" "imported" {
  bucket = "lab42-import-demo-REPLACE_WITH_TIMESTAMP"

  tags = {
    ManagedBy = "terraform"
  }
}
```

```bash
terraform init

# Import the bucket
terraform import aws_s3_bucket.imported lab42-import-demo-REPLACE_WITH_TIMESTAMP

# Expected output:
# aws_s3_bucket.imported: Importing from ID "lab42-import-demo-..."
# aws_s3_bucket.imported: Import prepared!
# Import successful!

# Verify
terraform plan
# Should show minimal or no changes

# Clean up
terraform destroy -auto-approve
```

> **Tip:** After importing, always run `terraform plan` to detect drift between your config and the actual resource. Adjust your HCL until `plan` shows no changes.

---

## Summary

| Use Case | Tools | Pattern |
|----------|-------|---------|
| IaC Migration | `terraform import`, import blocks | Write config, import state, iterate |
| Config Management | Terraform + Ansible | Provision infra, then configure |
| Immutable Infra | Packer + Terraform | Build AMI, deploy from AMI |
| CI/CD | Jenkins, GitHub Actions | Plan on PR, apply on merge |
| Version Management | tfenv | `.terraform-version` per project |
| Code Quality | pre-commit | Format, validate, lint, security |
| PR Workflow | Atlantis | Plan on PR comment, apply on approve |
| DRY at Scale | Terragrunt | Wrapper for multi-env, multi-module |
| Remote Execution | Terraform Cloud | Managed state, remote runs, VCS hooks |
