# 042 — Terraform Provisioners: file, local-exec, remote-exec

**By:** Saravanan Sundaramoorthy
**Environment:** Local + AWS ap-south-1 (remote-exec demo needs AWS)
**Time:** ~20 minutes

---

## Topic

A **provisioner** is a block inside a resource that runs a script or copies a file immediately after the resource is created (or just before it is destroyed). Provisioners let you bridge the gap between "resource exists" and "resource is configured."

Terraform ships with three built-in provisioners:

| Provisioner | Runs where | What it does |
|---|---|---|
| `local-exec` | Your local machine | Runs any shell command locally |
| `file` | Remote server (needs connection) | Copies a file or directory to the remote server |
| `remote-exec` | Remote server (needs connection) | Runs commands on the remote server via SSH or WinRM |

### Why Terraform recommends against provisioners

> "Provisioners are a last resort. Use `user_data`, `cloud-init`, or a configuration management tool instead."
> — HashiCorp Terraform Docs

The reason: provisioners run only at creation time (or destroy time with `when = destroy`). Terraform has no way to detect drift in what the provisioner did. If the script fails halfway through, the resource is in an unknown state. Terraform cannot re-run provisioners on an already-created resource unless you `taint` it and recreate it.

Use provisioners when:
- You have no other option (e.g., a legacy system with no cloud-init support)
- You need a one-shot action that is inherently idempotent
- You are calling an external tool like Ansible that manages idempotency itself

---

## Provisioner vs Alternatives — Comparison Table

| Approach | Drift detection | Idempotent | Runs at | Best for |
|---|---|---|---|---|
| `local-exec` provisioner | No | Manual | Creation / destroy | Calling external tools |
| `file` provisioner | No | Yes (overwrites) | Creation | Copying config files |
| `remote-exec` provisioner | No | Manual | Creation | One-shot setup scripts |
| `user_data` / cloud-init | No (runs once) | Designed for it | First boot | Package install, basic config |
| Ansible (via local-exec) | Yes (Ansible handles it) | Yes | Post-creation | Full configuration management |
| Packer (baked AMI) | Yes (new AMI = new state) | Yes | Build time | Golden image pipeline |

---

## Project Layout

```
terraform-provisioners-042-demo/
├── providers.tf
├── variables.tf
├── main.tf          (three demos)
├── outputs.tf
└── scripts/
    └── setup.sh
```

---

## Step 1 — Create the project directory

```bash
mkdir terraform-provisioners-042-demo
cd terraform-provisioners-042-demo
mkdir scripts
```

---

## Step 2 — providers.tf

```hcl
# providers.tf
terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

---

## Step 3 — variables.tf

```hcl
# variables.tf
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "ami_id" {
  description = "Ubuntu 22.04 LTS AMI in ap-south-1"
  type        = string
  default     = "ami-0f58b397bc5c1f2e8"   # Ubuntu 22.04 ap-south-1 (verify before use)
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}
```

---

## Step 4 — scripts/setup.sh

This is the script that will be copied to the server and executed by remote-exec.

```bash
#!/bin/bash
# scripts/setup.sh
# Idempotent setup script for robochef.co

set -e

echo "[setup.sh] Starting setup for robochef.co at $(date)"

# Update package lists
apt-get update -y

# Install nginx if not already present
if ! command -v nginx &>/dev/null; then
  apt-get install -y nginx
  echo "[setup.sh] nginx installed"
else
  echo "[setup.sh] nginx already present, skipping install"
fi

# Start and enable nginx
systemctl enable nginx
systemctl start nginx

echo "[setup.sh] Setup complete for robochef.co at $(date)"
```

Make it executable locally (the file provisioner copies permissions too):

```bash
chmod +x scripts/setup.sh
```

---

## Step 5 — main.tf

### Demo 1 — local-exec (no AWS needed)

`local-exec` runs a command on your local machine after the resource is created. The `null_resource` has no real infrastructure — it is a container for provisioners.

```hcl
# main.tf

# ── Demo 1: local-exec ──────────────────────────────────────────────────────

resource "null_resource" "local_script" {
  provisioner "local-exec" {
    command = "echo 'Deployed robochef.co at $(date)' >> /tmp/deploy-log.txt"
  }

  provisioner "local-exec" {
    command     = "echo 'Checking Python version...'; python3 --version"
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "null_resource" "on_destroy" {
  provisioner "local-exec" {
    when    = destroy
    command = "echo 'Cleaning up robochef.co resources...' >> /tmp/deploy-log.txt"
  }
}
```

**How the `interpreter` argument works:**

By default `local-exec` runs the command string through `/bin/sh -c`. If you need bash-specific features (arrays, `[[ ]]`, process substitution), set `interpreter = ["/bin/bash", "-c"]`.

You can also call Python:

```hcl
provisioner "local-exec" {
  interpreter = ["python3", "-c"]
  command     = "print('Hello from Python provisioner')"
}
```

**`when = destroy` explained:**

By default all provisioners run at creation. Adding `when = destroy` makes the provisioner run just before Terraform destroys the resource. Use this for cleanup tasks such as:
- De-registering the instance from a load balancer
- Notifying a monitoring system
- Writing a destroy timestamp to a log

---

### Demo 2 — Generate SSH Key and Launch EC2

The `file` and `remote-exec` provisioners both need SSH access to the remote server. We generate a key pair with Terraform's `tls` provider so no manual key management is needed.

```hcl
# ── Demo 2 + 3 setup: SSH key + EC2 ────────────────────────────────────────

resource "tls_private_key" "demo" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "private_key" {
  filename        = "/tmp/terraform-042-demo.pem"
  content         = tls_private_key.demo.private_key_pem
  file_permission = "0600"
}

resource "aws_key_pair" "demo" {
  key_name   = "terraform-042-demo"
  public_key = tls_private_key.demo.public_key_openssh
}

resource "aws_security_group" "demo" {
  name        = "terraform-042-provisioner-sg"
  description = "Allow SSH for provisioner demo"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # restrict to your IP in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.demo.key_name
  vpc_security_group_ids      = [aws_security_group.demo.id]
  associate_public_ip_address = true

  tags = {
    Name    = "robochef-provisioner-demo"
    Project = "terraform-042"
  }
}
```

---

### Demo 2 — file provisioner (copies files to remote)

```hcl
# ── Demo 2: file provisioner ────────────────────────────────────────────────

resource "null_resource" "file_copy" {
  depends_on = [aws_instance.web]

  # Re-run this resource if the instance is replaced
  triggers = {
    instance_id = aws_instance.web.id
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.demo.private_key_pem
    host        = aws_instance.web.public_ip
    timeout     = "2m"
  }

  provisioner "file" {
    source      = "scripts/setup.sh"
    destination = "/tmp/setup.sh"
  }
}
```

The `connection` block tells Terraform how to reach the server. Every `file` and `remote-exec` provisioner inside the same resource inherits the connection unless overridden.

**connection block arguments:**

| Argument | Description |
|---|---|
| `type` | `"ssh"` (Linux) or `"winrm"` (Windows) |
| `user` | SSH username — `ubuntu` for Ubuntu AMIs, `ec2-user` for Amazon Linux |
| `private_key` | PEM-encoded private key string |
| `host` | IP or hostname of the remote server |
| `timeout` | How long to wait for SSH to become available |

**file provisioner arguments:**

| Argument | Description |
|---|---|
| `source` | Local path to the file or directory |
| `destination` | Absolute path on the remote server |

To copy a whole directory: set `source = "scripts/"` and `destination = "/tmp/scripts"`.

---

### Demo 3 — remote-exec (run commands on remote server)

```hcl
# ── Demo 3: remote-exec provisioner ────────────────────────────────────────

resource "null_resource" "remote_commands" {
  depends_on = [null_resource.file_copy]

  triggers = {
    instance_id = aws_instance.web.id
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.demo.private_key_pem
    host        = aws_instance.web.public_ip
    timeout     = "2m"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup.sh",
      "sudo /tmp/setup.sh",
      "echo 'Setup complete for robochef.co'"
    ]
  }
}
```

**remote-exec arguments:**

| Argument | Type | Description |
|---|---|---|
| `inline` | list(string) | List of commands; run in order; fails on first non-zero exit |
| `script` | string | Path to a local script; Terraform uploads it then runs it |
| `scripts` | list(string) | Like `script` but for multiple scripts; run in order |

Use `inline` when the commands are short. Use `script` or `scripts` when the logic is complex and belongs in a version-controlled file.

---

### on_failure behaviour

By default, if a provisioner command fails (non-zero exit code), Terraform marks the resource as **tainted** and fails the apply. On the next apply, Terraform will destroy and recreate the tainted resource, then retry the provisioner.

```hcl
provisioner "local-exec" {
  command    = "curl https://monitoring.example.com/notify || true"
  on_failure = continue   # ignore errors from this provisioner
}
```

| `on_failure` value | Behaviour |
|---|---|
| `fail` (default) | Taint the resource and halt apply |
| `continue` | Log the error but continue apply |

Use `continue` only for non-critical side-effect provisioners (e.g., sending a notification). Never use `continue` on provisioners that perform critical setup.

---

## Step 6 — outputs.tf

```hcl
# outputs.tf
output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = try(aws_instance.web.public_ip, "not created")
}

output "private_key_path" {
  description = "Local path to the generated private key"
  value       = local_sensitive_file.private_key.filename
}

output "deploy_log" {
  description = "Local deploy log path written by local-exec provisioners"
  value       = "/tmp/deploy-log.txt"
}
```

---

## Step 7 — Apply

### Demo 1 only (no AWS)

Comment out or remove the EC2-related resources and apply just the `null_resource.local_script` and `null_resource.on_destroy` blocks.

```bash
terraform init
terraform apply -auto-approve
cat /tmp/deploy-log.txt
```

Expected in /tmp/deploy-log.txt:
```
Deployed robochef.co at Thu May 21 08:30:00 UTC 2026
```

### Full apply (requires AWS credentials)

```bash
export AWS_ACCESS_KEY_ID=<your-key>
export AWS_SECRET_ACCESS_KEY=<your-secret>

terraform init
terraform plan
terraform apply -auto-approve
```

Watch the provisioner output in the apply log:

```
null_resource.file_copy: Provisioning with 'file'...
null_resource.file_copy: Still creating... [10s elapsed]
null_resource.remote_commands: Provisioning with 'remote-exec'...
null_resource.remote_commands (remote-exec): [setup.sh] Starting setup for robochef.co at ...
null_resource.remote_commands (remote-exec): [setup.sh] nginx installed
null_resource.remote_commands (remote-exec): [setup.sh] Setup complete for robochef.co at ...
```

---

## Step 8 — Verify on the Remote Server

```bash
ssh -i /tmp/terraform-042-demo.pem ubuntu@<public-ip>
systemctl status nginx
curl http://localhost
```

---

## Step 9 — Common Issues

### SSH connection timeout
The EC2 instance needs 30–60 seconds after creation before SSH is available. The `timeout = "2m"` in the connection block handles this — Terraform will retry until SSH responds or the timeout is reached.

If your instances regularly take longer, increase the timeout:
```hcl
connection {
  timeout = "5m"
  ...
}
```

### Permission denied on private key
The private key file must be `0600`. The `file_permission = "0600"` argument on `local_sensitive_file` sets this automatically.

```bash
# Manual fix if needed:
chmod 600 /tmp/terraform-042-demo.pem
```

### Provisioner doesn't re-run after a change
Provisioners only run at creation. To force re-run:
1. `terraform taint null_resource.remote_commands` — marks the resource for destruction/recreation
2. `terraform apply` — destroys and recreates, running provisioners again

Or use the `triggers` map in `null_resource` to re-run whenever a tracked value changes:
```hcl
triggers = {
  script_hash = filemd5("scripts/setup.sh")
}
```
Every time `setup.sh` changes, the `null_resource` is replaced and the provisioners re-run.

---

## Key Concepts Summary

| Concept | Detail |
|---|---|
| `local-exec` | Runs on your local machine; no SSH needed |
| `file` | Copies files to remote; needs `connection` block |
| `remote-exec` | Runs commands on remote; needs `connection` block |
| `when = destroy` | Provisioner runs at destroy instead of creation |
| `on_failure = continue` | Ignore provisioner errors and continue apply |
| `null_resource` | A resource with no infrastructure; used as a container for provisioners |
| `triggers` | Re-run the `null_resource` when a value changes |
| Taint | `terraform taint <resource>` forces recreation on next apply |
| Last resort | Prefer `user_data`, cloud-init, or Ansible over provisioners |

---

## Cleanup

```bash
terraform destroy -auto-approve
rm -rf .terraform
```

The private key at `/tmp/terraform-042-demo.pem` is managed by Terraform and will be deleted by `terraform destroy`. The deploy log at `/tmp/deploy-log.txt` is not managed — remove it manually if desired:

```bash
rm -f /tmp/deploy-log.txt
```

---

## What's Next

- **Lab 043** — Terraform + Ansible Integration via local-exec
