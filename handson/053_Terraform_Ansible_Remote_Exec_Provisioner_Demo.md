# Lab 053 — Terraform Ansible Remote-Exec Provisioner Demo
**By: Saravanan Sundaramoorthy**
**Environment:** Local + AWS ap-south-1
**Time:** ~30 minutes

---

## Topic

This lab demonstrates how to use Terraform's `remote-exec` provisioner to run a deployment script on a freshly created EC2 instance — without needing Ansible installed locally. The script installs Nginx and Ansible on the remote server and drops a custom `index.html`, simulating what a real application deployment pipeline does.

This pattern is adapted from an Azure VM demo that used SSH password authentication. Here we use AWS EC2 with a Terraform-generated ED25519 key pair — the correct approach for any production-leaning environment.

### The two-provisioner pattern

```
terraform apply
    │
    └── aws_instance.web is created
            │
            └── null_resource.deploy_stack fires (depends_on aws_instance.web)
                    │
                    ├── file provisioner
                    │       copies robochef_stack.sh → /tmp/robochef_stack.sh on EC2
                    │
                    └── remote-exec provisioner
                            chmod +x /tmp/robochef_stack.sh
                            sudo /tmp/robochef_stack.sh
                                │
                                └── apt-get installs nginx + ansible
                                    systemctl enables nginx
                                    writes custom index.html
```

The `file` provisioner copies a local script to the remote machine. The `remote-exec` provisioner then executes it. Together they are the Terraform-native way to bootstrap a server when cloud-init is not practical or when you need to coordinate with an external tool like Ansible.

---

## Teaching Points

### 1 — Why remote-exec?

`remote-exec` runs commands directly on the remote machine over SSH. You do not need Ansible, Python, or any configuration management tool installed on your local workstation. This makes it useful in CI pipelines where agent images are minimal.

### 2 — The two-step file + remote-exec pattern

Terraform's `file` provisioner cannot execute a file — it only copies it. To both copy and run a script:

1. Use `file` to copy the script to `/tmp/` on the remote host.
2. Use `remote-exec` to `chmod +x` the script and then execute it as root via `sudo`.

Putting both inside the same `null_resource` keeps the dependency explicit and the log output together.

### 3 — SSH connection block

The `connection` block tells Terraform how to reach the remote machine:

```hcl
connection {
  type        = "ssh"
  host        = aws_instance.web.public_ip
  user        = "ubuntu"             # Ubuntu AMI default user
  private_key = tls_private_key.demo.private_key_openssh
}
```

Never use `password` in a `connection` block for anything beyond a quick throwaway demo. Always use key-based authentication. The `tls_private_key` resource generates the key pair in memory; Terraform stores the private key in state (which is why the state file must be protected).

### 4 — `on_failure = continue` vs `on_failure = fail`

| Setting | Behaviour |
|---|---|
| `on_failure = fail` (default) | Terraform marks the resource as tainted and halts. The next `apply` destroys and re-creates it. |
| `on_failure = continue` | Terraform logs the error and continues. The resource is NOT tainted. Use only when the provisioner is advisory (e.g., a monitoring hook that is optional). |

For deployment scripts use the default `fail` so failures are always visible.

### 5 — Provisioner runs before instance is ready

EC2 reports RUNNING before SSHd is accepting connections. If Terraform tries the `remote-exec` connection too early the apply fails with:

```
Error: timeout - last error: dial tcp x.x.x.x:22: connect: connection refused
```

Solutions (pick one):
- Add `sleep 20` as the first line in `remote-exec` `inline` commands (quick, not elegant).
- Use `aws_instance` `user_data` to install a readiness signal (proper approach for production).
- Set a longer timeout in the `connection` block: `timeout = "5m"` (Terraform retries until the timeout is hit).

The `connection` block's default timeout is already 5 minutes, so for most t3.micro instances in ap-south-1 you will connect successfully within 30–60 seconds.

### 6 — When to use Ansible vs remote-exec

| Criterion | Use `remote-exec` | Use Ansible |
|---|---|---|
| Script complexity | Simple (< 30 lines, no templating) | Complex (roles, templates, conditionals) |
| Idempotency | Script handles it manually | Ansible modules are idempotent by design |
| Audit trail | Basic (Terraform log) | Full Ansible facts + reports |
| Inventory management | Single host | Multiple hosts, groups, dynamic inventory |
| Local dependencies | None (SSH only) | Requires Ansible on the control machine |
| Day-2 re-runs | Taint + re-apply | `ansible-playbook` directly, no taint needed |

Use `remote-exec` to bootstrap the server quickly. Graduate to Ansible when the configuration grows or needs to be re-applied independently of Terraform.

---

## Prerequisites

### AWS credentials

```bash
export AWS_ACCESS_KEY_ID=<your-access-key>
export AWS_SECRET_ACCESS_KEY=<your-secret-key>
export AWS_DEFAULT_REGION=ap-south-1
```

### Local tools

```bash
terraform -version   # >= 1.3
ssh -V               # OpenSSH client (for manual verification)
curl --version       # for verification step
```

Ansible does NOT need to be installed locally for this lab. It is installed on the EC2 instance by the deployment script.

---

## Project Layout

```
terraform-ansible-remote-exec-053/
├── providers.tf
├── variables.tf
├── main.tf
├── outputs.tf
└── scripts/
    └── robochef_stack.sh
```

---

## Step 1 — Create the project directory

```bash
mkdir ~/terraform-ansible-remote-exec-053
cd ~/terraform-ansible-remote-exec-053
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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
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
  description = "AWS region to deploy into"
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
  default     = "robochef"
}
```

---

## Step 4 — The deployment script

Write this file before running `terraform apply`. The `file` provisioner uploads it verbatim.

```bash
cat > scripts/robochef_stack.sh << 'EOF'
#!/bin/bash
set -e

echo "=== robochef_stack.sh starting ==="

apt-get update -y
apt-get install -y nginx ansible

systemctl start nginx
systemctl enable nginx

echo "Hello from robochef.co — deployed by Ansible+Terraform remote-exec" \
  > /var/www/html/index.html

echo "=== robochef_stack.sh complete ==="
EOF

chmod +x scripts/robochef_stack.sh
```

Full script content for reference:

```bash
#!/bin/bash
set -e

echo "=== robochef_stack.sh starting ==="

apt-get update -y
apt-get install -y nginx ansible

systemctl start nginx
systemctl enable nginx

echo "Hello from robochef.co — deployed by Ansible+Terraform remote-exec" \
  > /var/www/html/index.html

echo "=== robochef_stack.sh complete ==="
```

`set -e` causes the script to exit immediately on any command failure. This ensures Terraform sees a non-zero exit code and marks the `null_resource` as failed rather than silently continuing.

---

## Step 5 — main.tf

```hcl
# main.tf

# ─── SSH key pair ───────────────────────────────────────────────────────────

resource "tls_private_key" "demo" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "demo" {
  key_name   = "${var.project_name}-key-053"
  public_key = tls_private_key.demo.public_key_openssh

  tags = {
    Name    = "${var.project_name}-key-053"
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}

# Save private key locally so you can SSH manually
resource "local_file" "private_key" {
  content         = tls_private_key.demo.private_key_openssh
  filename        = "${path.module}/robochef_demo.pem"
  file_permission = "0600"
}

# ─── Networking ─────────────────────────────────────────────────────────────

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "web" {
  name        = "${var.project_name}-sg-053"
  description = "Allow SSH and HTTP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
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

  tags = {
    Name    = "${var.project_name}-sg-053"
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}

# ─── AMI lookup ─────────────────────────────────────────────────────────────

data "aws_ami" "ubuntu_22" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ─── EC2 instance ────────────────────────────────────────────────────────────

resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu_22.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.demo.key_name
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true

  tags = {
    Name    = "${var.project_name}-web-053"
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}

# ─── Remote provisioning via null_resource ───────────────────────────────────
#
# We use null_resource so that the provisioner lifecycle is independent of the
# EC2 resource. Destroying and re-creating null_resource re-runs the script
# without terminating the EC2 instance — useful during development.

resource "null_resource" "deploy_stack" {
  # Re-run if the instance is replaced or the script changes
  triggers = {
    instance_id = aws_instance.web.id
    script_hash = filemd5("${path.module}/scripts/robochef_stack.sh")
  }

  connection {
    type        = "ssh"
    host        = aws_instance.web.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.demo.private_key_openssh
    timeout     = "5m"
  }

  # Step 1: copy the script to the remote machine
  provisioner "file" {
    source      = "${path.module}/scripts/robochef_stack.sh"
    destination = "/tmp/robochef_stack.sh"
  }

  # Step 2: make it executable and run it as root
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/robochef_stack.sh",
      "sudo /tmp/robochef_stack.sh",
    ]

    # on_failure = fail   # This is the default. Uncomment to make explicit.
    # on_failure = continue  # Use only for optional/advisory steps.
  }

  depends_on = [aws_instance.web]
}
```

---

## Step 6 — outputs.tf

```hcl
# outputs.tf

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.web.id
}

output "public_ip" {
  description = "Public IP of the web server"
  value       = aws_instance.web.public_ip
}

output "public_dns" {
  description = "Public DNS of the web server"
  value       = aws_instance.web.public_dns
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i robochef_demo.pem ubuntu@${aws_instance.web.public_ip}"
}

output "curl_command" {
  description = "curl command to verify the web server"
  value       = "curl http://${aws_instance.web.public_ip}"
}

output "key_algorithm" {
  description = "Algorithm used for the SSH key"
  value       = tls_private_key.demo.algorithm
}
```

---

## Step 7 — Run Terraform

### Init

```bash
cd ~/terraform-ansible-remote-exec-053
terraform init
```

Expected output:

```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Finding hashicorp/tls versions matching "~> 4.0"...
- Finding hashicorp/local versions matching "~> 2.0"...
- Finding hashicorp/null versions matching "~> 3.0"...
- Installing hashicorp/aws v6.x.x...
- Installing hashicorp/tls v4.x.x...
- Installing hashicorp/local v2.x.x...
- Installing hashicorp/null v3.x.x...

Terraform has been successfully initialized!
```

### Plan

```bash
terraform plan
```

Expected resource summary:

```
Plan: 6 to add, 0 to change, 0 to destroy.

  + aws_instance.web
  + aws_key_pair.demo
  + aws_security_group.web
  + local_file.private_key
  + null_resource.deploy_stack
  + tls_private_key.demo
```

### Apply

```bash
terraform apply -auto-approve
```

Expected output (abbreviated):

```
tls_private_key.demo: Creating...
tls_private_key.demo: Creation complete after 0s [id=...]

aws_key_pair.demo: Creating...
aws_security_group.web: Creating...
local_file.private_key: Creating...
local_file.private_key: Creation complete after 0s [id=...]
aws_key_pair.demo: Creation complete after 1s [id=robochef-key-053]
aws_security_group.web: Creation complete after 2s [id=sg-0abc123...]

aws_instance.web: Creating...
aws_instance.web: Still creating... [10s elapsed]
aws_instance.web: Still creating... [20s elapsed]
aws_instance.web: Still creating... [30s elapsed]
aws_instance.web: Creation complete after 35s [id=i-0abc123def456...]

null_resource.deploy_stack: Creating...
null_resource.deploy_stack: Provisioning with 'file'...
null_resource.deploy_stack: Provisioning with 'remote-exec'...
null_resource.deploy_stack (remote-exec): Connecting to remote host via SSH...
null_resource.deploy_stack (remote-exec):   Host: 13.235.x.x
null_resource.deploy_stack (remote-exec):   User: ubuntu
null_resource.deploy_stack (remote-exec):   Password: false
null_resource.deploy_stack (remote-exec):   Private key: true
null_resource.deploy_stack (remote-exec):   Certificate: false
null_resource.deploy_stack (remote-exec):   SSH Agent: false
null_resource.deploy_stack (remote-exec):   Checking Host Key: false
null_resource.deploy_stack (remote-exec): Connected!
null_resource.deploy_stack (remote-exec): === robochef_stack.sh starting ===
null_resource.deploy_stack (remote-exec): Hit:1 http://ap-south-1.ec2.archive.ubuntu.com/ubuntu jammy InRelease
null_resource.deploy_stack (remote-exec): Get:2 http://ap-south-1.ec2.archive.ubuntu.com/ubuntu jammy-updates InRelease
null_resource.deploy_stack (remote-exec): ...
null_resource.deploy_stack (remote-exec): Reading package lists...
null_resource.deploy_stack (remote-exec): Building dependency tree...
null_resource.deploy_stack (remote-exec): The following NEW packages will be installed:
null_resource.deploy_stack (remote-exec):   nginx ansible ...
null_resource.deploy_stack (remote-exec): Setting up nginx (1.18.0-6ubuntu14.4) ...
null_resource.deploy_stack (remote-exec): Setting up ansible (5.10.0-1) ...
null_resource.deploy_stack (remote-exec): Synchronizing state of nginx.service...
null_resource.deploy_stack (remote-exec): === robochef_stack.sh complete ===
null_resource.deploy_stack: Creation complete after 2m 15s [id=...]

Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:

curl_command   = "curl http://13.235.x.x"
instance_id    = "i-0abc123def456..."
key_algorithm  = "ED25519"
public_dns     = "ec2-13-235-x-x.ap-south-1.compute.amazonaws.com"
public_ip      = "13.235.x.x"
ssh_command    = "ssh -i robochef_demo.pem ubuntu@13.235.x.x"
```

---

## Step 8 — Verify the deployment

### Check the web server via curl

```bash
curl http://$(terraform output -raw public_ip)
```

Expected output:

```
Hello from robochef.co — deployed by Ansible+Terraform remote-exec
```

### SSH into the instance and inspect

```bash
ssh -i robochef_demo.pem ubuntu@$(terraform output -raw public_ip)
```

Once connected:

```bash
# Check nginx is running
systemctl status nginx

# Check Ansible version installed on the remote machine
ansible --version

# Re-read the index.html
cat /var/www/html/index.html
```

Expected `systemctl status nginx` excerpt:

```
● nginx.service - A high performance web server and a reverse proxy server
     Loaded: loaded (/lib/systemd/system/nginx.service; enabled; vendor preset: enabled)
     Active: active (running) since Thu 2026-05-21 10:xx:xx UTC; Xmin ago
```

---

## Step 9 — Optional: run_ansible null_resource with local-exec

If you want Terraform to also trigger an Ansible playbook from the local machine (requiring Ansible installed locally), add a second `null_resource`:

```hcl
# Optional — add to main.tf after null_resource.deploy_stack

resource "null_resource" "run_ansible" {
  triggers = {
    deploy_id   = null_resource.deploy_stack.id
    playbook_md5 = filemd5("${path.module}/playbooks/site.yml")
  }

  provisioner "local-exec" {
    command = <<-EOT
      ANSIBLE_HOST_KEY_CHECKING=False \
      ansible-playbook \
        -i '${aws_instance.web.public_ip},' \
        --user ubuntu \
        --private-key ${path.module}/robochef_demo.pem \
        ${path.module}/playbooks/site.yml
    EOT
  }

  depends_on = [null_resource.deploy_stack]
}
```

And a minimal Ansible playbook at `playbooks/site.yml`:

```yaml
---
- name: Verify robochef.co stack
  hosts: all
  become: false
  gather_facts: false

  tasks:
    - name: Wait for SSH to be available
      ansible.builtin.wait_for_connection:
        timeout: 60

    - name: Check nginx service is running
      become: true
      ansible.builtin.systemd:
        name: nginx
        state: started
        enabled: true

    - name: Verify index.html content
      ansible.builtin.command: cat /var/www/html/index.html
      register: page_content
      changed_when: false

    - name: Show page content
      ansible.builtin.debug:
        var: page_content.stdout
```

This second `null_resource` uses `local-exec` — it runs the Ansible playbook from your workstation against the remote host. The combination (remote-exec to bootstrap, local-exec + Ansible to configure) is a common real-world pattern.

---

## Step 10 — Trigger a re-run without destroying EC2

Because the provisioners live in `null_resource.deploy_stack` rather than in `aws_instance.web`, you can re-run the deployment script without replacing the EC2 instance:

```bash
terraform taint null_resource.deploy_stack
terraform apply -auto-approve
```

Terraform destroys and re-creates only `null_resource.deploy_stack`. The EC2 instance, security group, and key pair are untouched.

This is one of the main reasons to use `null_resource` for provisioners instead of embedding them inside the `aws_instance` resource block.

---

## Common Errors and Fixes

### Error: timeout — connection refused

```
Error: timeout - last error: dial tcp 13.235.x.x:22: connect: connection refused
```

**Cause:** EC2 reached RUNNING state but SSHd has not started yet.
**Fix:** The `connection` block retries for the duration of `timeout` (default 5 minutes). This usually resolves itself within 60 seconds for t3.micro. If it still fails, confirm the security group allows inbound TCP/22 from `0.0.0.0/0`.

---

### Error: Permission denied (publickey)

```
Error: error waiting for provisioner to complete:
ssh: handshake failed: ssh: unable to authenticate
```

**Cause:** The key passed in `private_key` does not match the key on the instance, or the `user` is wrong.
**Fix:** For Ubuntu 22.04 AMIs the default user is `ubuntu`. For Amazon Linux it is `ec2-user`. Verify with:

```bash
ssh -i robochef_demo.pem -v ubuntu@<public_ip> 2>&1 | grep "Authentications that can continue"
```

---

### Error: no such file or directory (file provisioner)

```
Error: upload failed: open scripts/robochef_stack.sh: no such file or directory
```

**Cause:** The `source` path in the `file` provisioner is relative to the working directory when you run `terraform apply`, not relative to `path.module`.
**Fix:** The `main.tf` uses `"${path.module}/scripts/robochef_stack.sh"` which is always absolute. Make sure the `scripts/` directory exists before running `apply`.

---

### Script fails partway through

If the script exits with a non-zero code (e.g., `apt-get` hits a temporary mirror error), Terraform marks `null_resource.deploy_stack` as tainted:

```
null_resource.deploy_stack: Provisioning with 'remote-exec'...
null_resource.deploy_stack (remote-exec): E: Could not get lock /var/lib/apt/lists/lock
╷
│ Error: remote-exec provisioner error
│ Error running command 'sudo /tmp/robochef_stack.sh': exit status 100
│ Output: ...
```

Fix the underlying issue (e.g., wait for `unattended-upgrades` to finish), then:

```bash
terraform apply -auto-approve
```

Terraform automatically re-creates the tainted `null_resource` and re-runs the script.

---

## Cleanup

```bash
terraform destroy -auto-approve
rm -rf .terraform
```

Expected output:

```
null_resource.deploy_stack: Destroying... [id=...]
null_resource.deploy_stack: Destruction complete after 0s
aws_instance.web: Destroying... [id=i-0abc123def456...]
aws_instance.web: Still destroying... [10s elapsed]
aws_instance.web: Destruction complete after 35s
aws_security_group.web: Destroying... [id=sg-0abc123...]
aws_security_group.web: Destruction complete after 1s
aws_key_pair.demo: Destroying... [id=robochef-key-053]
aws_key_pair.demo: Destruction complete after 0s
local_file.private_key: Destroying... [id=...]
local_file.private_key: Destruction complete after 0s
tls_private_key.demo: Destroying... [id=...]
tls_private_key.demo: Destruction complete after 0s

Destroy complete! Resources: 6 destroyed.
```

Remove the local PEM file and the project directory:

```bash
rm -f robochef_demo.pem
cd ~
rm -rf ~/terraform-ansible-remote-exec-053
```

---

## Summary

| Resource | Purpose |
|---|---|
| `tls_private_key.demo` | Generates ED25519 SSH key pair in memory |
| `aws_key_pair.demo` | Registers the public key with AWS |
| `local_file.private_key` | Saves the private key locally for manual SSH access |
| `aws_security_group.web` | Allows inbound SSH (22) and HTTP (80) |
| `aws_instance.web` | Ubuntu 22.04 t3.micro in ap-south-1 |
| `null_resource.deploy_stack` | Runs the `file` + `remote-exec` provisioners |

### Key takeaways

- The `file` provisioner copies; the `remote-exec` provisioner runs. Always use them as a pair.
- Put provisioners in `null_resource` rather than inside `aws_instance` so you can re-run them without destroying the EC2 instance.
- Set `timeout` in the `connection` block to tolerate SSH startup delay on fresh instances.
- Use `on_failure = fail` (the default) for deployment scripts so errors surface immediately.
- Graduate to Ansible for complex configuration management. Use `remote-exec` for simple, one-shot bootstrap scripts.
- Always protect the Terraform state file — it contains the plaintext private key from `tls_private_key`.
