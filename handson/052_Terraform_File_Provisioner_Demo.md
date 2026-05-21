# Lab 052 — Terraform File Provisioner Demo
**By: Saravanan Sundaramoorthy**
**Environment:** Local + AWS ap-south-1
**Time:** ~25 minutes

---

## Topic

The **`file` provisioner** copies a local file (or directory) to a remote server over SSH immediately after the resource is created. It is the simplest of the three built-in Terraform provisioners, but it comes with an important caveat:

> **`file` copies — it does not execute.**

To run a copied script you must pair `file` with a `remote-exec` provisioner.

### How it compares to the other provisioners

| Provisioner | Runs on | What it does | Needs SSH/WinRM? |
|---|---|---|---|
| `local-exec` | Your laptop/CI machine | Runs any local shell command | No |
| `file` | Remote server | Copies a file or directory | Yes |
| `remote-exec` | Remote server | Executes commands on the remote host | Yes |

### When to use `file`

- You need to drop a config file, environment file, or bash script on a newly created server before running it.
- You are bootstrapping a VM that has no cloud-init or user-data support.
- You want a Terraform-managed one-shot file delivery step (e.g., seeding a cron script).

### Why Terraform considers provisioners a "last resort"

Provisioners run only once — at creation time (or at destroy time with `when = destroy`). Terraform cannot detect drift in what the provisioner wrote. If the script fails halfway through, the resource is left in an unknown state. Terraform has no way to re-run the provisioner on an already-running instance without tainting the resource and recreating it.

Prefer `user_data` / `cloud-init` or a configuration-management tool (Ansible, Chef) when possible. Use provisioners for legacy targets or quick demo / lab scenarios like this one.

---

## What We Build

```
robochef.co — file provisioner demo
┌────────────────────────────────────────────────────────────────────┐
│  Your laptop                                                       │
│  ┌──────────────┐   file provisioner   ┌───────────────────────┐  │
│  │  data.txt    │ ──────────────────▶  │  EC2 Ubuntu 22.04     │  │
│  │              │                      │  /tmp/data.txt         │  │
│  └──────────────┘                      │                        │  │
│  ┌──────────────┐   file provisioner   │  /tmp/robochef_stack.sh│  │
│  │robochef_     │ ──────────────────▶  │                        │  │
│  │stack.sh      │                      │                        │  │
│  └──────────────┘   remote-exec        │  nginx running         │  │
│                  ──────────────────▶   │  /var/www/html/index   │  │
│                  sudo bash /tmp/...    │    .html               │  │
└────────────────────────────────────────────────────────────────────┘
```

Files copied to the EC2 instance:

| Local file | Remote destination | Purpose |
|---|---|---|
| `data.txt` | `/tmp/data.txt` | Static config info for robochef.co |
| `robochef_stack.sh` | `/tmp/robochef_stack.sh` | Install nginx + write index.html |

After copying, a `remote-exec` provisioner runs `sudo bash /tmp/robochef_stack.sh`.

---

## Project Layout

```
~/terraform-file-provisioner-052/
├── providers.tf
├── variables.tf
├── terraform.tfvars
├── main.tf
├── outputs.tf
├── data.txt
└── robochef_stack.sh
```

---

## Step 1 — Create the Project Directory

```bash
mkdir -p ~/terraform-file-provisioner-052
cd ~/terraform-file-provisioner-052
```

---

## Step 2 — Create the Local Files That Will Be Copied

### `data.txt` — static config data

```bash
cat > data.txt << 'EOF'
# robochef.co — deployment config
# File provisioner demo — Lab 052

app_name    = robochef.co
environment = demo
region      = ap-south-1
version     = 1.0.0
deployed_by = Terraform file provisioner
managed_by  = Saravanan Sundaramoorthy

# Notes
# This file is copied from the Terraform working directory
# to /tmp/data.txt on the EC2 instance using the file provisioner.
# It is NOT executed — it is just a plain text file.
EOF
```

### `robochef_stack.sh` — setup script

```bash
cat > robochef_stack.sh << 'EOF'
#!/usr/bin/env bash
# robochef_stack.sh
# Installed by Terraform file provisioner + remote-exec
# Lab 052 — robochef.co

set -euo pipefail

echo "=== robochef.co stack setup starting ==="

# Update package list and install nginx
apt-get update -y
apt-get install -y nginx

# Enable and start nginx
systemctl enable nginx
systemctl start nginx

# Write a custom landing page
cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>robochef.co</title>
</head>
<body>
  <h1>Hello from robochef.co deployed by Terraform file provisioner</h1>
  <p>This page was created by robochef_stack.sh, which was copied to
     /tmp/robochef_stack.sh using the Terraform <code>file</code>
     provisioner and then executed with <code>remote-exec</code>.</p>
</body>
</html>
HTMLEOF

echo "=== robochef.co stack setup complete ==="
EOF

chmod +x robochef_stack.sh
```

---

## Step 3 — `providers.tf`

```hcl
terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

---

## Step 4 — `variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "project_name" {
  description = "Short name used in resource names and tags"
  type        = string
  default     = "robochef-fp-052"
}

variable "owner" {
  description = "Owner tag value"
  type        = string
  default     = "saravanans"
}

variable "project_tag" {
  description = "Project tag value"
  type        = string
  default     = "robochef.co"
}
```

---

## Step 5 — `terraform.tfvars`

```hcl
aws_region    = "ap-south-1"
instance_type = "t3.micro"
project_name  = "robochef-fp-052"
owner         = "saravanans"
project_tag   = "robochef.co"
```

---

## Step 6 — `main.tf`

This is the heart of the lab. Read through the inline comments carefully.

```hcl
# ─────────────────────────────────────────────────────────────
# DATA SOURCES — AMI, VPC, Subnets
# ─────────────────────────────────────────────────────────────

# Ubuntu 22.04 LTS (Jammy) — official Canonical AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]   # Canonical's AWS account

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Use the default VPC — no custom networking required for this lab
data "aws_vpc" "default" {
  default = true
}

# Pull all subnets in the default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ─────────────────────────────────────────────────────────────
# TLS PRIVATE KEY — ED25519, Terraform-managed
# ─────────────────────────────────────────────────────────────

# Generate a fresh ED25519 key pair every time.
# The public key goes into AWS as a Key Pair.
# The private key is stored in Terraform state (sensitive) and
# also written to disk so the file provisioner connection can use it.
resource "tls_private_key" "demo" {
  algorithm = "ED25519"
}

# Save the private key to disk so we can SSH manually if needed.
# file_permission = "0600" prevents "permissions too open" SSH errors.
resource "local_file" "private_key" {
  content         = tls_private_key.demo.private_key_openssh
  filename        = "${path.module}/robochef-fp-052.pem"
  file_permission = "0600"
}

# Register the public half with AWS
resource "aws_key_pair" "demo" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.demo.public_key_openssh

  tags = {
    Name    = "${var.project_name}-key"
    Owner   = var.owner
    Project = var.project_tag
  }
}

# ─────────────────────────────────────────────────────────────
# SECURITY GROUP — SSH (22) ingress, all egress
# ─────────────────────────────────────────────────────────────

resource "aws_security_group" "demo" {
  name        = "${var.project_name}-sg"
  description = "Allow SSH ingress for file-provisioner demo"
  vpc_id      = data.aws_vpc.default.id

  # SSH — needed for both file provisioner and remote-exec provisioner
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP — to verify nginx after script runs
  ingress {
    description = "HTTP to verify nginx"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Owner   = var.owner
    Project = var.project_tag
  }
}

# ─────────────────────────────────────────────────────────────
# EC2 INSTANCE — with file provisioner + remote-exec provisioner
# ─────────────────────────────────────────────────────────────

resource "aws_instance" "demo" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.demo.id]
  key_name                    = aws_key_pair.demo.key_name
  associate_public_ip_address = true

  tags = {
    Name    = "${var.project_name}-ec2"
    Owner   = var.owner
    Project = var.project_tag
  }

  # ── CONNECTION BLOCK ─────────────────────────────────────────
  # Defined at the resource level so ALL provisioners inside this
  # resource share the same connection settings.
  # The private key is read directly from the tls_private_key resource —
  # no local file path needed for the connection itself.
  connection {
    type        = "ssh"
    user        = "ubuntu"             # Ubuntu 22.04 default user
    host        = self.public_ip
    private_key = tls_private_key.demo.private_key_openssh
    timeout     = "4m"
  }

  # ── PROVISIONER 1: file — copy data.txt ──────────────────────
  #
  # Teaching point:
  #   • `source`      = local path (relative to the Terraform working dir)
  #   • `destination` = absolute path on the remote server
  #   • The file provisioner ONLY copies. It does NOT run anything.
  #   • Destination must be writable by the SSH user.
  #     /tmp is always writable, so it is a safe landing zone.
  #
  provisioner "file" {
    source      = "${path.module}/data.txt"
    destination = "/tmp/data.txt"
  }

  # ── PROVISIONER 2: file — copy the setup script ──────────────
  #
  # Teaching point:
  #   • Copying a shell script does NOT execute it.
  #   • The script lands at /tmp/robochef_stack.sh with whatever
  #     permissions the SSH user can set — usually 644 by default.
  #   • We will use remote-exec next to actually run it with sudo.
  #
  provisioner "file" {
    source      = "${path.module}/robochef_stack.sh"
    destination = "/tmp/robochef_stack.sh"
  }

  # ── PROVISIONER 3: remote-exec — run the copied script ───────
  #
  # Teaching point:
  #   • `inline` runs commands in order, one per list element.
  #   • We first chmod the script to ensure it is executable,
  #     then run it with sudo (nginx install requires root).
  #   • Provisioners in the same resource run in declaration order:
  #     file (data.txt) → file (script) → remote-exec.
  #
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/robochef_stack.sh",
      "sudo bash /tmp/robochef_stack.sh",
    ]
  }

  # Ensure the TLS key is fully created before this resource attempts
  # its SSH connection.
  depends_on = [tls_private_key.demo]
}

# ─────────────────────────────────────────────────────────────
# NULL RESOURCE DEMO — file provisioner outside an EC2 resource
# ─────────────────────────────────────────────────────────────
#
# Teaching point:
#   Sometimes you want to copy a file to an already-running instance
#   without recreating it. A null_resource with a trigger on a
#   content hash lets you re-run the file provisioner whenever
#   the source file changes — without touching the EC2 resource.
#
resource "null_resource" "recopy_data" {
  # Re-run whenever data.txt changes
  triggers = {
    data_txt_hash = filemd5("${path.module}/data.txt")
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = aws_instance.demo.public_ip
    private_key = tls_private_key.demo.private_key_openssh
    timeout     = "4m"
  }

  provisioner "file" {
    source      = "${path.module}/data.txt"
    destination = "/tmp/data.txt"
  }

  depends_on = [aws_instance.demo]
}
```

---

## Step 7 — `outputs.tf`

```hcl
output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.demo.id
}

output "public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.demo.public_ip
}

output "public_dns" {
  description = "Public DNS name of the EC2 instance"
  value       = aws_instance.demo.public_dns
}

output "ami_id" {
  description = "Ubuntu 22.04 AMI selected by the data source"
  value       = data.aws_ami.ubuntu.id
}

output "key_pair_name" {
  description = "AWS Key Pair name"
  value       = aws_key_pair.demo.key_name
}

output "private_key_file" {
  description = "Path to the local private key file"
  value       = local_file.private_key.filename
}

output "ssh_command" {
  description = "Paste this to SSH into the instance"
  value       = "ssh -i robochef-fp-052.pem ubuntu@${aws_instance.demo.public_ip}"
}

output "nginx_url" {
  description = "URL to verify nginx is running"
  value       = "http://${aws_instance.demo.public_ip}"
}
```

---

## Step 8 — Initialize and Apply

```bash
cd ~/terraform-file-provisioner-052

terraform init
terraform validate
terraform plan
terraform apply -auto-approve
```

### Expected output — `terraform init`

```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Finding hashicorp/tls versions matching "~> 4.0"...
- Finding hashicorp/local versions matching "~> 2.0"...
- Installing hashicorp/aws v6.x.x...
- Installing hashicorp/tls v4.x.x...
- Installing hashicorp/local v2.x.x...
Terraform has been successfully initialized!
```

### Expected output — `terraform apply`

```
data.aws_vpc.default: Reading...
data.aws_vpc.default: Read complete after 1s [id=vpc-0abc12345]
data.aws_subnets.default: Reading...
data.aws_subnets.default: Read complete after 1s [id=...]
data.aws_ami.ubuntu: Reading...
data.aws_ami.ubuntu: Read complete after 2s [id=ami-0f5ee92e2d63afc18]

Terraform will perform the following actions:

  # aws_instance.demo will be created
  + resource "aws_instance" "demo" {
      + ami                         = "ami-0f5ee92e2d63afc18"
      + instance_type               = "t3.micro"
      + associate_public_ip_address = true
      ...
    }

  # aws_key_pair.demo will be created
  + resource "aws_key_pair" "demo" { ... }

  # aws_security_group.demo will be created
  + resource "aws_security_group" "demo" { ... }

  # tls_private_key.demo will be created
  + resource "tls_private_key" "demo" { ... }

  # local_file.private_key will be created
  + resource "local_file" "private_key" { ... }

  # null_resource.recopy_data will be created
  + resource "null_resource" "recopy_data" { ... }

Plan: 6 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

tls_private_key.demo: Creating...
tls_private_key.demo: Creation complete after 0s [id=...]
local_file.private_key: Creating...
local_file.private_key: Creation complete after 0s [id=...]
aws_key_pair.demo: Creating...
aws_key_pair.demo: Creation complete after 1s [id=robochef-fp-052-key]
aws_security_group.demo: Creating...
aws_security_group.demo: Creation complete after 2s [id=sg-0abc123456]
aws_instance.demo: Creating...
aws_instance.demo: Still creating... [10s elapsed]
aws_instance.demo: Still creating... [20s elapsed]
aws_instance.demo: Still creating... [30s elapsed]
aws_instance.demo: Provisioning with 'file'...    ← data.txt being copied
aws_instance.demo: Still creating... [40s elapsed]
aws_instance.demo: Provisioning with 'file'...    ← robochef_stack.sh being copied
aws_instance.demo: Provisioning with 'remote-exec'...
aws_instance.demo (remote-exec): Connecting via SSH...
aws_instance.demo (remote-exec): Connected!
aws_instance.demo (remote-exec): =================================
aws_instance.demo (remote-exec): === robochef.co stack setup starting ===
aws_instance.demo (remote-exec): Hit:1 http://ap-south-1.ec2.archive.ubuntu.com/ubuntu jammy InRelease
aws_instance.demo (remote-exec): Reading package lists... Done
aws_instance.demo (remote-exec): Building dependency tree... Done
aws_instance.demo (remote-exec): Reading state information... Done
aws_instance.demo (remote-exec): The following packages will be installed:
aws_instance.demo (remote-exec):   nginx nginx-common ...
aws_instance.demo (remote-exec): Processing triggers for systemd (249-14ubuntu3.6) ...
aws_instance.demo (remote-exec): Created symlink /etc/systemd/system/multi-user.target.wants/nginx.service
aws_instance.demo (remote-exec): === robochef.co stack setup complete ===
aws_instance.demo: Creation complete after 1m32s [id=i-0abc1234567890abc]
null_resource.recopy_data: Creating...
null_resource.recopy_data: Provisioning with 'file'...
null_resource.recopy_data: Creation complete after 2s [id=1234567890123456789]

Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:

ami_id           = "ami-0f5ee92e2d63afc18"
instance_id      = "i-0abc1234567890abc"
key_pair_name    = "robochef-fp-052-key"
nginx_url        = "http://13.233.xxx.xxx"
private_key_file = "/home/ubuntu/terraform-file-provisioner-052/robochef-fp-052.pem"
public_dns       = "ec2-13-233-xxx-xxx.ap-south-1.compute.amazonaws.com"
public_ip        = "13.233.xxx.xxx"
ssh_command      = "ssh -i robochef-fp-052.pem ubuntu@13.233.xxx.xxx"
```

---

## Step 9 — Verify the Deployment

### Check that both files were copied

```bash
ssh -i robochef-fp-052.pem ubuntu@$(terraform output -raw public_ip) \
  "ls -lh /tmp/data.txt /tmp/robochef_stack.sh"
```

Expected:

```
-rw-r--r-- 1 ubuntu ubuntu  387 May 21 10:15 /tmp/data.txt
-rw-r--r-- 1 ubuntu ubuntu  742 May 21 10:15 /tmp/robochef_stack.sh
```

### Confirm nginx is running

```bash
ssh -i robochef-fp-052.pem ubuntu@$(terraform output -raw public_ip) \
  "systemctl is-active nginx"
```

Expected: `active`

### View the landing page content

```bash
curl -s http://$(terraform output -raw public_ip)
```

Expected:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>robochef.co</title>
</head>
<body>
  <h1>Hello from robochef.co deployed by Terraform file provisioner</h1>
  <p>This page was created by robochef_stack.sh, which was copied to
     /tmp/robochef_stack.sh using the Terraform <code>file</code>
     provisioner and then executed with <code>remote-exec</code>.</p>
</body>
</html>
```

### View the copied data.txt on the remote instance

```bash
ssh -i robochef-fp-052.pem ubuntu@$(terraform output -raw public_ip) \
  "cat /tmp/data.txt"
```

Expected:

```
# robochef.co — deployment config
# File provisioner demo — Lab 052

app_name    = robochef.co
environment = demo
region      = ap-south-1
version     = 1.0.0
deployed_by = Terraform file provisioner
managed_by  = Saravanan Sundaramoorthy
...
```

---

## Step 10 — Trigger the null_resource Re-copy

Edit `data.txt` locally to simulate a config change:

```bash
echo "updated_at = $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> data.txt
```

Run apply again:

```bash
terraform apply -auto-approve
```

Expected — only the `null_resource` reruns (EC2 is untouched):

```
null_resource.recopy_data: Destroying... [id=...]
null_resource.recopy_data: Destruction complete after 0s
null_resource.recopy_data: Creating...
null_resource.recopy_data: Provisioning with 'file'...
null_resource.recopy_data: Creation complete after 2s [id=...]

Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

Verify the updated file on the remote instance:

```bash
ssh -i robochef-fp-052.pem ubuntu@$(terraform output -raw public_ip) \
  "tail -2 /tmp/data.txt"
```

---

## Key Teaching Points — Summary

### 1. `file` copies, it does not execute

```hcl
provisioner "file" {
  source      = "robochef_stack.sh"
  destination = "/tmp/robochef_stack.sh"
}
# The script is now on the server but has NOT been run.
```

### 2. Pair `file` with `remote-exec` to run the script

```hcl
provisioner "remote-exec" {
  inline = [
    "chmod +x /tmp/robochef_stack.sh",
    "sudo bash /tmp/robochef_stack.sh",
  ]
}
```

### 3. The `connection` block can be at resource level or inline

**Resource-level (shared by all provisioners in the resource):**

```hcl
resource "aws_instance" "demo" {
  ...
  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = self.public_ip
    private_key = tls_private_key.demo.private_key_openssh
  }

  provisioner "file" { ... }      # uses the resource-level connection
  provisioner "remote-exec" { ... } # uses the resource-level connection
}
```

**Inline (overrides per provisioner if you need different credentials):**

```hcl
provisioner "file" {
  source      = "data.txt"
  destination = "/tmp/data.txt"

  connection {              # overrides resource-level connection
    type        = "ssh"
    user        = "ubuntu"
    host        = aws_instance.demo.public_ip
    private_key = tls_private_key.demo.private_key_openssh
  }
}
```

### 4. Provisioners run in declaration order

```hcl
provisioner "file" { ... }         # runs first
provisioner "file" { ... }         # runs second
provisioner "remote-exec" { ... }  # runs third
```

### 5. Use `depends_on` to ensure the key exists before SSH

```hcl
resource "aws_instance" "demo" {
  ...
  depends_on = [tls_private_key.demo]
}
```

Without this, Terraform might try to open an SSH connection before the `tls_private_key` resource has finished generating.

### 6. Use `null_resource` + `triggers` to re-run provisioners without recreating the EC2 instance

```hcl
resource "null_resource" "recopy_data" {
  triggers = {
    data_txt_hash = filemd5("${path.module}/data.txt")
  }
  connection { ... }
  provisioner "file" { ... }
  depends_on = [aws_instance.demo]
}
```

Every time `data.txt` changes its MD5, the `null_resource` is destroyed and recreated — which re-runs the `file` provisioner — without touching the EC2 instance.

---

## Common Errors and Fixes

| Error | Cause | Fix |
|---|---|---|
| `Error: timeout - last error: SSH authentication handshake failed` | Instance not yet ready or SG missing port 22 | Increase `timeout`, verify security group ingress rule on port 22 |
| `Error: dial tcp: connection refused` | Instance booting, SSH daemon not up yet | Terraform retries automatically; if persistent, check the AMI is Ubuntu and the user is `ubuntu` |
| `Error: ssh: no key found` | `private_key` not set in connection block | Ensure `private_key = tls_private_key.demo.private_key_openssh` |
| `Error: open data.txt: no such file or directory` | `source` path is wrong or file does not exist | Check path; use `${path.module}/data.txt` for absolute resolution |
| `Error: Permission denied (publickey)` | Wrong SSH user or wrong key | Ubuntu 22.04 uses user `ubuntu`; verify key pair matches |
| `/tmp/robochef_stack.sh: Permission denied` | Script not made executable before `bash` | Add `chmod +x /tmp/robochef_stack.sh` as the first inline command |

---

## Step 11 — Cleanup

```bash
cd ~/terraform-file-provisioner-052

terraform destroy -auto-approve

rm -rf .terraform
rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl
rm -f robochef-fp-052.pem
```

Verify all resources are gone in the AWS console (EC2, Key Pairs, Security Groups).

---

## Full Provisioner Reference Table

| Provisioner | Runs on | Needs SSH/WinRM | What it does | Best for |
|---|---|---|---|---|
| `file` | Remote server | Yes | Copies a local file or directory to the remote host | Seeding config files, scripts, certificates onto a new VM |
| `local-exec` | Local machine (where `terraform apply` runs) | No | Runs any shell command locally after resource creation | Calling Ansible, triggering a CI pipeline, writing a local file |
| `remote-exec` | Remote server | Yes | Runs a list of commands or a script on the remote host via SSH | One-shot package installs, bootstrap scripts, idempotent setup steps |

### When to choose each

| Scenario | Recommended approach |
|---|---|
| Install packages and configure app on a new VM | `user_data` / cloud-init (preferred) or `remote-exec` provisioner |
| Drop a config file on a VM without rebuilding it | `null_resource` + `file` provisioner + `triggers` |
| Run Ansible after VM creation | `local-exec` provisioner calling `ansible-playbook` |
| Notify an external system (Slack, PagerDuty) after apply | `local-exec` provisioner with `curl` |
| Create a golden AMI with software pre-installed | Packer (not a provisioner — bake the AMI before Terraform runs) |
| Copy a TLS certificate to a VM | `file` provisioner |
| Run a script that already exists on the remote VM | `remote-exec` provisioner |

---

## Further Reading

- [Terraform Provisioners — Official Docs](https://developer.hashicorp.com/terraform/language/resources/provisioners/syntax)
- [file Provisioner](https://developer.hashicorp.com/terraform/language/resources/provisioners/file)
- [remote-exec Provisioner](https://developer.hashicorp.com/terraform/language/resources/provisioners/remote-exec)
- [local-exec Provisioner](https://developer.hashicorp.com/terraform/language/resources/provisioners/local-exec)
- [null_resource](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource)
- [tls_private_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key)

---

*Lab 052 — robochef.co File Provisioner Demo — By: Saravanan Sundaramoorthy*
