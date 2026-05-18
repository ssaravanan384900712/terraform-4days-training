# Lab 1.1 - Infrastructure as Code Foundations

Infrastructure as Code (IaC) is the practice of managing and provisioning computing infrastructure through machine-readable configuration files rather than through manual processes or interactive tools. This lab introduces the core concepts behind IaC, traces its evolution from ad hoc scripts to modern provisioning tools, and positions Terraform within this landscape. By the end of this module you will understand **why** IaC matters, **how** Terraform works at a high level, and **how it compares** to alternatives.

---

## 1. The Rise of DevOps

Traditionally, development teams wrote code and "threw it over the wall" to operations teams who manually provisioned servers, configured networks, and deployed applications. This led to:

- Slow release cycles (weeks or months)
- Environment drift between dev, staging, and production
- Finger-pointing between Dev and Ops when things broke
- No reproducibility -- each server was a "snowflake"

**DevOps** emerged as a cultural and technical movement to break down these silos. Key principles include:

| Principle | Description |
|-----------|-------------|
| **Collaboration** | Dev and Ops work together throughout the lifecycle |
| **Automation** | Automate everything: builds, tests, deploys, infrastructure |
| **Continuous Delivery** | Ship small changes frequently and safely |
| **Measurement** | Monitor everything, use feedback loops |
| **Sharing** | Share tools, knowledge, and responsibility |

> **Note:** DevOps is not a tool or a job title -- it is a set of practices. IaC is one of the most important technical practices within DevOps.

---

## 2. What is Infrastructure as Code?

Infrastructure as Code means you define your infrastructure (servers, networks, databases, load balancers, DNS entries, IAM policies, etc.) in **code files** that can be:

- **Version controlled** in Git alongside application code
- **Reviewed** through pull requests
- **Tested** automatically
- **Reused** across environments
- **Audited** for compliance

### Before IaC (Manual Process)

```
1. Log into AWS Console
2. Click "Launch Instance"
3. Select AMI, instance type, VPC, subnet, security group...
4. Click "Launch"
5. SSH in and install packages manually
6. Repeat for every environment
7. Hope you remember what you did 6 months later
```

### After IaC (Automated Process)

```hcl
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  tags = {
    Name = "web-server"
  }
}
```

```bash
terraform apply   # Done. Reproducible. Documented. Versioned.
```

---

## 3. Ad Hoc Scripts -- Where It All Started

The simplest form of IaC is a shell script:

```bash
#!/bin/bash
# setup-server.sh

# Update packages
sudo yum update -y

# Install Apache
sudo yum install -y httpd

# Start Apache
sudo systemctl start httpd
sudo systemctl enable httpd

# Deploy app
sudo cp /tmp/index.html /var/www/html/

echo "Server setup complete"
```

### Limitations of Ad Hoc Scripts

| Limitation | Description |
|------------|-------------|
| **Not idempotent** | Running twice may produce different results or errors |
| **No state tracking** | Script doesn't know what already exists |
| **Hard to maintain** | Grows into spaghetti code with edge-case handling |
| **No rollback** | No built-in way to undo changes |
| **Imperative** | You must specify every step, in order |
| **Platform-specific** | Bash scripts don't work on Windows; PowerShell doesn't work on Linux |

> **Tip:** Ad hoc scripts are fine for one-off tasks, but they break down when you need to manage infrastructure at scale across multiple environments.

---

## 4. Configuration Management Tools

Configuration Management (CM) tools evolved to address the limitations of ad hoc scripts.

### Chef

- Uses Ruby-based DSL called "recipes" and "cookbooks"
- Client-server architecture with a Chef Server
- Agent (chef-client) runs on each managed node
- Procedural style -- order of recipes matters

### Puppet

- Uses its own declarative language
- Client-server architecture with a Puppet Master
- Agent runs on each managed node
- Declarative style -- you describe desired state

### Ansible

- Uses YAML-based "playbooks"
- **Agentless** -- connects via SSH (Linux) or WinRM (Windows)
- No master server required (though Ansible Tower exists)
- Procedural style, but with idempotent modules

### Example: Ansible Playbook

```yaml
---
- name: Setup web server
  hosts: webservers
  become: yes
  tasks:
    - name: Install Apache
      yum:
        name: httpd
        state: present

    - name: Start Apache
      service:
        name: httpd
        state: started
        enabled: yes
```

### What CM Tools Do Well

- Install and configure software on existing servers
- Enforce desired state of OS-level configurations
- Manage packages, files, services, and users

### What CM Tools Do NOT Do Well

- Provision the servers themselves (VMs, networks, load balancers)
- Manage cloud-native resources (S3 buckets, RDS databases, IAM roles)
- Handle immutable infrastructure patterns (replace rather than update)

---

## 5. Provisioning Tools

Provisioning tools are designed specifically to create, modify, and destroy infrastructure resources.

### Terraform (HashiCorp)

- Open-source, multi-cloud provisioning tool
- Uses HCL (HashiCorp Configuration Language)
- Declarative approach
- Agentless, masterless
- Immutable infrastructure philosophy
- Tracks state in a state file

### AWS CloudFormation

- AWS-native provisioning tool
- Uses JSON or YAML templates
- Declarative approach
- Only works with AWS
- State managed by AWS service

### Pulumi

- Multi-cloud provisioning tool
- Uses real programming languages (Python, TypeScript, Go, C#)
- Imperative approach with declarative engine
- Tracks state in Pulumi Cloud or local backend

---

## 6. Benefits of IaC

### 6.1 Self-Service

Developers can provision their own infrastructure by running Terraform code, without filing tickets or waiting for Ops.

### 6.2 Speed and Safety

```
Manual process:  2 hours to provision a staging environment
IaC process:     5 minutes to run "terraform apply"
```

### 6.3 Documentation

The code IS the documentation. You can read `main.tf` and know exactly what infrastructure exists.

### 6.4 Version Control

```bash
git log --oneline
# a1b2c3d Add RDS database for user service
# d4e5f6g Update instance type to t3.medium
# h7i8j9k Initial VPC and subnet setup
```

### 6.5 Validation

```bash
terraform validate   # Syntax check
terraform plan       # Preview changes before applying
# Plus: automated tests, policy checks (Sentinel, OPA)
```

### 6.6 Reuse

Write a module once, use it across 10 environments:

```hcl
module "vpc" {
  source = "./modules/vpc"
  cidr   = "10.0.0.0/16"
  env    = "production"
}

module "vpc_staging" {
  source = "./modules/vpc"
  cidr   = "10.1.0.0/16"
  env    = "staging"
}
```

### 6.7 Consistency

Every environment is built from the same code. No more "works on my machine" for infrastructure.

---

## 7. How Terraform Works

Terraform follows a simple four-step workflow:

```
 Write (.tf files)
    |
    v
 terraform init      <-- Download providers and modules
    |
    v
 terraform plan      <-- Preview what will change
    |
    v
 terraform apply     <-- Create/modify/destroy resources
    |
    v
 terraform destroy   <-- Tear down everything (when done)
```

### 7.1 Write

You write `.tf` files in HCL describing your desired infrastructure:

```hcl
provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "example" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
}
```

### 7.2 Init

```bash
$ terraform init

Initializing the backend...
Initializing provider plugins...
- Finding latest version of hashicorp/aws...
- Installing hashicorp/aws v5.31.0...
- Installed hashicorp/aws v5.31.0 (signed by HashiCorp)

Terraform has been successfully initialized!
```

This step:
- Downloads the required provider plugins (e.g., AWS, Azure, GCP)
- Downloads referenced modules
- Initializes the backend (where state is stored)
- Creates the `.terraform/` directory

### 7.3 Plan

```bash
$ terraform plan

Terraform will perform the following actions:

  # aws_instance.example will be created
  + resource "aws_instance" "example" {
      + ami                          = "ami-0c55b159cbfafe1f0"
      + instance_type                = "t2.micro"
      + id                           = (known after apply)
      + public_ip                    = (known after apply)
      ...
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

This step:
- Reads current state
- Compares desired state (your code) with current state
- Shows what will be created (+), changed (~), or destroyed (-)
- Does NOT make any changes

### 7.4 Apply

```bash
$ terraform apply

  # aws_instance.example will be created
  + resource "aws_instance" "example" { ... }

Do you want to perform these actions?
  Enter a value: yes

aws_instance.example: Creating...
aws_instance.example: Still creating... [10s elapsed]
aws_instance.example: Creation complete after 35s [id=i-0abc123def456789]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

This step:
- Shows the plan and asks for confirmation
- Makes the actual API calls to create/modify/destroy resources
- Updates the state file with the new resource information

### 7.5 Destroy

```bash
$ terraform destroy

  # aws_instance.example will be destroyed
  - resource "aws_instance" "example" { ... }

Do you want to perform these actions?
  Enter a value: yes

aws_instance.example: Destroying... [id=i-0abc123def456789]
aws_instance.example: Destruction complete after 30s

Destroy complete! Resources: 1 destroyed.
```

---

## 8. Terraform vs Other Tools -- Comparison Matrix

| Feature | Terraform | CloudFormation | Ansible | Chef | Puppet | Pulumi |
|---------|-----------|---------------|---------|------|--------|--------|
| **Type** | Provisioning | Provisioning | Config Mgmt | Config Mgmt | Config Mgmt | Provisioning |
| **Language** | HCL | JSON/YAML | YAML | Ruby DSL | Puppet DSL | Python/TS/Go |
| **Style** | Declarative | Declarative | Procedural | Procedural | Declarative | Imperative |
| **Infrastructure** | Immutable | Immutable | Mutable | Mutable | Mutable | Immutable |
| **Agent** | Agentless | Agentless | Agentless | Agent | Agent | Agentless |
| **Master** | Masterless | Masterless | Masterless* | Master | Master | Masterless |
| **Cloud Support** | Multi-cloud | AWS only | Multi-cloud | Multi-cloud | Multi-cloud | Multi-cloud |
| **State** | State file | Managed by AWS | No state | Chef Server | Puppet Master | State file |
| **Community** | Very Large | Large (AWS) | Very Large | Medium | Medium | Growing |
| **License** | BSL 1.1 | Proprietary | GPL | Apache 2.0 | Apache 2.0 | Apache 2.0 |

> \* Ansible Tower / AWX provides a centralized management server, but it is optional.

### Mutable vs Immutable Infrastructure

**Mutable (Configuration Management approach):**
```
Server v1 --> apply update --> Server v1 (modified in-place)
                               (configuration drift risk)
```

**Immutable (Terraform approach):**
```
Server v1 --> destroy --> Server v2 (brand new from image)
                          (clean, no drift)
```

### Procedural vs Declarative

**Procedural (Ansible):** "Create 5 servers" -- if you run it again, you get 10 servers.

```yaml
# Run 1: Creates 5 servers (total: 5)
# Run 2: Creates 5 more servers (total: 10)
- ec2:
    count: 5
    image: ami-0c55b159cbfafe1f0
    instance_type: t2.micro
```

**Declarative (Terraform):** "There should be 5 servers" -- running again changes nothing.

```hcl
# Run 1: Creates 5 servers (total: 5)
# Run 2: No changes (total: still 5)
resource "aws_instance" "example" {
  count         = 5
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
}
```

### Agent-Based vs Agentless

**Agent-based (Chef, Puppet):**
- Requires software installed on every managed server
- Agent periodically contacts master for updates
- Additional maintenance burden
- Network connectivity required between agent and master

**Agentless (Terraform, Ansible):**
- No software to install on managed servers
- Terraform uses cloud provider APIs directly
- Ansible uses SSH
- Simpler architecture, less maintenance

---

## 9. Why Terraform?

Given the comparison above, Terraform stands out because:

1. **Multi-cloud** -- Single tool for AWS, Azure, GCP, and 3000+ providers
2. **Declarative** -- Describe what you want, not how to get there
3. **Immutable** -- Replace rather than patch, reducing drift
4. **Agentless & Masterless** -- Nothing to install or maintain beyond the CLI
5. **Plan before apply** -- Always preview changes before making them
6. **State management** -- Knows what exists and can detect drift
7. **Massive community** -- Thousands of modules, providers, and examples
8. **Open core** -- Free CLI with optional paid features (Terraform Cloud/Enterprise)

---

## 10. Knowledge Check

Answer these questions to confirm your understanding:

1. What is the primary difference between Configuration Management and Provisioning tools?
2. Why are ad hoc scripts insufficient for managing infrastructure at scale?
3. What does "declarative" mean in the context of IaC?
4. What are the four main Terraform commands in order?
5. Why is immutable infrastructure preferred over mutable infrastructure?
6. Name two advantages Terraform has over AWS CloudFormation.
7. What does `terraform plan` do, and why is it important?

> **Tip:** Revisit these questions after completing the hands-on labs. The concepts will become much clearer once you have applied them in practice.

---

## Summary

| Concept | Key Takeaway |
|---------|-------------|
| DevOps | Culture + automation; IaC is a core practice |
| Ad hoc scripts | Simple but fragile, not idempotent, no state |
| Config Management | Great for software on servers, not for provisioning |
| Provisioning tools | Create and manage cloud infrastructure |
| Terraform | Declarative, immutable, agentless, multi-cloud |
| Workflow | Write -> init -> plan -> apply -> destroy |

In the next lab, you will install Terraform and write your first configuration file.
