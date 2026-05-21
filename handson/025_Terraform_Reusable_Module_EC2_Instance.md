# 025 — Writing a Reusable Terraform Module for EC2 Instance Launch

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~25 minutes

---

## Topic

A **Terraform module** is a self-contained, reusable package of Terraform configuration. Instead of copy-pasting the same EC2, security group, and key-pair blocks across every project, you write them once inside a module and call them from anywhere.

This is the **DRY principle** (Don't Repeat Yourself) applied to infrastructure:

```text
Without modules                     With modules
─────────────────────────           ─────────────────────────
project-a/main.tf  ← EC2 block      module/ec2-instance/
project-b/main.tf  ← EC2 block        ├── main.tf      ← written once
project-c/main.tf  ← EC2 block        ├── variables.tf
                                       └── outputs.tf

                                    project-a/main.tf  ← module "web" { source = ... }
                                    project-b/main.tf  ← module "app" { source = ... }
                                    project-c/main.tf  ← module "db"  { source = ... }
```

Why modules matter:

- **Reusability** — write once, call from multiple projects or environments
- **Consistency** — all EC2 instances follow the same structure and conventions
- **Encapsulation** — callers only need to supply inputs; internals are hidden
- **Maintainability** — fix a bug in the module, every caller benefits
- **Team scale** — platform teams publish modules; app teams consume them

In this lab you will:

1. Understand the difference between a module and a root module
2. Learn why modules must NOT contain a `provider` block
3. Learn how `merge()` combines module-default tags with caller-provided tags
4. Create the `ec2-instance` module at `~/terraform-modules/ec2-instance/`
5. Write all three module files (`variables.tf`, `main.tf`, `outputs.tf`)
6. Preview how lab 027 will call this module

> **Note:** This lab only creates module files — no `terraform init`, no `terraform apply`.
> The module is not deployed here. It is tested in **lab 027**.

---

## Module vs Root Module

| Term | Meaning |
|---|---|
| **Root module** | The directory where you run `terraform apply`. Contains `provider` blocks and `terraform.tfvars`. |
| **Module** | A reusable component called from a root module via `module "name" { source = "..." }`. No `provider` block of its own. |
| **Child module** | Another name for any module that is called by a root module. |

The key rule: **modules inherit providers from their caller.** A module must not define its own `provider` block because that would lock the module to a single provider configuration and prevent callers from customising the region, profile, or assume-role settings.

```text
Root module (caller)
  └── provider "aws" { region = "ap-south-1" }   ← provider lives here
  └── module "web_server" {
        source = "../../terraform-modules/ec2-instance"
        ...                                        ← module receives provider automatically
      }
```

---

## Module File Structure

A module contains exactly three files. There is no `providers.tf`, no `terraform.tfvars`, and no `backend` configuration — those belong to the root module that calls the module.

```text
terraform-modules/
└── ec2-instance/
    ├── main.tf        ← resources and data sources
    ├── variables.tf   ← input variables (the module's API)
    └── outputs.tf     ← output values (what callers can read back)
```

### Why no `providers.tf` in the module?

| File | In root module? | In module? | Reason |
|---|---|---|---|
| `providers.tf` | Yes | No | Module inherits the caller's provider |
| `terraform.tfvars` | Yes | No | Callers supply variable values |
| `backend.tf` | Yes | No | State is owned by the root module |
| `variables.tf` | Optional | Yes | Defines the module's input interface |
| `outputs.tf` | Optional | Yes | Exposes values back to the caller |
| `main.tf` | Yes | Yes | Contains resources |

---

## The `merge()` Function for Tags

The `merge()` function combines two or more maps, with later maps overriding keys from earlier ones:

```hcl
merge({ Name = "robochef-web-ssh-sg" }, var.tags)
```

This lets the module set a sensible default `Name` tag while still allowing the caller to pass in extra tags — or even override `Name` if they choose to:

```hcl
# Caller in lab 027
module "web_server" {
  source        = "../../terraform-modules/ec2-instance"
  instance_name = "robochef-web"
  tags = {
    Owner   = "saravanans"
    Project = "robochef.co"
    Env     = "staging"
  }
}

# Resulting tags on aws_security_group.ssh
# {
#   Name    = "robochef-web-ssh-sg"   ← from module default
#   Owner   = "saravanans"            ← from caller's tags
#   Project = "robochef.co"           ← from caller's tags
#   Env     = "staging"               ← from caller's tags
# }
```

---

## Step 1 — Create the Module Directory

```bash
mkdir -p ~/terraform-modules/ec2-instance
```

Verify:

```bash
ls ~/terraform-modules/ec2-instance
# (empty — files are created in the next steps)
```

---

## Step 2 — Write `variables.tf`

This file defines the module's input interface. Callers must supply `instance_name`. All other variables have defaults and are optional.

```bash
cat > ~/terraform-modules/ec2-instance/variables.tf << 'EOF'
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "private_key_path" {
  description = "Path where the generated private key is saved"
  type        = string
  default     = "~/.ssh/terraform-module-ec2"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed for SSH"
  type        = string
  default     = "0.0.0.0/0"
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
EOF
```

### Variable explanation

| Variable | Required? | Default | Purpose |
|---|---|---|---|
| `aws_region` | No | `ap-south-1` | AWS region — used by the caller's provider, not referenced directly in module resources |
| `instance_name` | **Yes** | none | Used to name the key pair, security group, and EC2 instance |
| `instance_type` | No | `t3.micro` | EC2 instance size |
| `private_key_path` | No | `~/.ssh/terraform-module-ec2` | Where the generated SSH private key is written on disk |
| `allowed_ssh_cidr` | No | `0.0.0.0/0` | Restrict SSH access; narrow this in production (e.g. your office IP) |
| `tags` | No | `{}` | Extra tags merged onto every resource |

> **Note on `aws_region`:** This variable is declared so callers can document which region they are targeting, but the actual provider configuration lives in the root module. The module does not call `provider "aws" { region = var.aws_region }`.

---

## Step 3 — Write `main.tf`

This file contains all the resources. Notice there is no `provider` block — the provider comes from whoever calls this module.

```bash
cat > ~/terraform-modules/ec2-instance/main.tf << 'EOF'
terraform {
  required_providers {
    aws   = { source = "hashicorp/aws",   version = "~> 6.0" }
    tls   = { source = "hashicorp/tls",   version = "~> 4.0" }
    local = { source = "hashicorp/local", version = "~> 2.0" }
  }
}

resource "tls_private_key" "this" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.this.private_key_openssh
  filename        = pathexpand(var.private_key_path)
  file_permission = "0600"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_key_pair" "this" {
  key_name   = "${var.instance_name}-key"
  public_key = tls_private_key.this.public_key_openssh
}

resource "aws_security_group" "ssh" {
  name        = "${var.instance_name}-ssh-sg"
  description = "Allow SSH"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({ Name = "${var.instance_name}-ssh-sg" }, var.tags)
}

resource "aws_instance" "this" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.this.key_name
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  associate_public_ip_address = true

  tags = merge({ Name = var.instance_name }, var.tags)
}
EOF
```

### Resource walkthrough

| Resource | Purpose |
|---|---|
| `tls_private_key.this` | Generates an ED25519 SSH key pair entirely in Terraform (no manual `ssh-keygen`) |
| `local_sensitive_file.private_key` | Writes the private key to disk at `var.private_key_path` with mode `0600`. Marked sensitive so its content is redacted in plan output. |
| `data.aws_ami.ubuntu` | Looks up the latest Ubuntu 22.04 LTS AMI in the caller's region (Canonical's AWS account `099720109477`) |
| `aws_key_pair.this` | Uploads the ED25519 public key to AWS so EC2 can inject it into the instance |
| `aws_security_group.ssh` | Opens port 22 inbound, all traffic outbound |
| `aws_instance.this` | Launches the EC2 instance with the key pair and security group attached |

### Why `terraform { required_providers { ... } }` in a module?

The `required_providers` block inside the module tells Terraform which provider sources and version constraints this module needs. The root module's `terraform init` uses this to download the correct providers. It is not the same as a `provider` block — it is a dependency declaration, not a configuration.

---

## Step 4 — Write `outputs.tf`

Outputs expose values from inside the module back to the root module (and any `terraform output` commands run there).

```bash
cat > ~/terraform-modules/ec2-instance/outputs.tf << 'EOF'
output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "EC2 public IP"
  value       = aws_instance.this.public_ip
}

output "ami_id" {
  description = "Ubuntu AMI used"
  value       = data.aws_ami.ubuntu.id
}

output "private_key_path" {
  description = "Path to generated private key"
  value       = local_sensitive_file.private_key.filename
}

output "ssh_command" {
  description = "SSH command"
  value       = "ssh -i ${pathexpand(var.private_key_path)} ubuntu@${aws_instance.this.public_ip}"
}
EOF
```

---

## Step 5 — Verify the Module Files

```bash
ls -1 ~/terraform-modules/ec2-instance/
```

Expected output:

```text
main.tf
outputs.tf
variables.tf
```

Review each file:

```bash
cat ~/terraform-modules/ec2-instance/variables.tf
cat ~/terraform-modules/ec2-instance/main.tf
cat ~/terraform-modules/ec2-instance/outputs.tf
```

---

## Module Input/Output Reference

### Inputs (`variables.tf`)

| Name | Type | Default | Required | Description |
|---|---|---|---|---|
| `aws_region` | `string` | `"ap-south-1"` | No | AWS region |
| `instance_name` | `string` | — | **Yes** | Name tag applied to instance, key pair, and security group |
| `instance_type` | `string` | `"t3.micro"` | No | EC2 instance type |
| `private_key_path` | `string` | `"~/.ssh/terraform-module-ec2"` | No | Local path where the SSH private key is written |
| `allowed_ssh_cidr` | `string` | `"0.0.0.0/0"` | No | CIDR block allowed for SSH inbound |
| `tags` | `map(string)` | `{}` | No | Additional tags merged onto all resources |

### Outputs (`outputs.tf`)

| Name | Description | Example value |
|---|---|---|
| `instance_id` | EC2 instance ID | `i-0abc1234def56789` |
| `public_ip` | EC2 public IP address | `13.235.45.67` |
| `ami_id` | Ubuntu 22.04 AMI that was used | `ami-0522ab6e1ddcc7055` |
| `private_key_path` | Full path to the private key on disk | `/home/saravanans/.ssh/terraform-module-ec2` |
| `ssh_command` | Ready-to-paste SSH command | `ssh -i ~/.ssh/terraform-module-ec2 ubuntu@13.235.45.67` |

---

## Preview: How Lab 027 Calls This Module

In lab 027 you will create a root module that calls `ec2-instance` twice — once for `robochef.co` and once for `chillbotindia.com`. Here is a preview of what that looks like:

```hcl
# lab-027/main.tf  (root module — NOT written in this lab)

provider "aws" {
  region = "ap-south-1"
}

module "web_server" {
  source        = "../../terraform-modules/ec2-instance"
  instance_name = "robochef-web"
  instance_type = "t3.micro"
  tags = {
    Owner   = "saravanans"
    Project = "robochef.co"
    Env     = "staging"
  }
}

module "chillbot_server" {
  source           = "../../terraform-modules/ec2-instance"
  instance_name    = "chillbot-web"
  instance_type    = "t3.micro"
  private_key_path = "~/.ssh/terraform-chillbot-ec2"
  tags = {
    Owner   = "saravanans"
    Project = "chillbotindia.com"
    Env     = "dev"
  }
}

output "robochef_ssh" {
  value = module.web_server.ssh_command
}

output "chillbot_ssh" {
  value = module.chillbot_server.ssh_command
}
```

After `terraform apply` in lab 027:

```text
Outputs:

robochef_ssh  = "ssh -i ~/.ssh/terraform-module-ec2 ubuntu@13.235.45.67"
chillbot_ssh  = "ssh -i ~/.ssh/terraform-chillbot-ec2 ubuntu@52.66.12.34"
```

Notice:
- The same module is called **twice** with different inputs
- Each call gets its own independent set of resources (key pair, security group, EC2 instance)
- Outputs are accessed as `module.<name>.<output_name>`
- The root module owns the `provider` block; the module never sees it directly

---

## Important Note

> **Do not delete the module files after this lab.**
> Lab 027 (`terraform apply`) reads `~/terraform-modules/ec2-instance/` at plan time.
> If the module directory is missing or incomplete, `terraform init` in lab 027 will fail.

---

## Concept Summary

| Concept | What it means |
|---|---|
| **Module** | A directory of `.tf` files that encapsulates a set of resources and is called from another Terraform configuration |
| **`source`** | The path (local) or registry address (remote) that tells Terraform where to find the module |
| **Variables** | The module's input API — callers set them; the module reads them via `var.<name>` |
| **Outputs** | Values the module exposes back to its caller, accessible as `module.<name>.<output>` |
| **`merge()`** | Built-in function that combines maps; later map's keys win on conflict — used here to blend module default tags with caller-supplied tags |
| **Reusability** | One module definition, called from many root modules or called multiple times in one root module with different inputs |
| **No `provider` in module** | Modules inherit the caller's provider configuration — defining one inside the module would lock it to a fixed region/profile and break portability |
| **`required_providers` in module** | Declares which providers the module depends on so `terraform init` can download them — this is a dependency declaration, not a provider configuration |
| **`pathexpand()`** | Expands `~` to the current user's home directory — important for writing SSH keys to `~/.ssh/` |
| **`local_sensitive_file`** | Like `local_file` but marks the content sensitive so it is redacted in plan/apply output |
