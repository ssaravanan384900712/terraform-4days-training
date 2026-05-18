# Lab 2.6 — Provisioners and Integrations

Terraform provisioners execute scripts or commands on local or remote machines as part of resource creation or destruction. While HashiCorp recommends using cloud-native tooling (user_data, AMI baking) wherever possible, provisioners remain essential for legacy workflows, configuration management integration, and bootstrapping scenarios where no other option exists. In this lab you will use the `file`, `local-exec`, and `remote-exec` provisioners, integrate Terraform with Ansible, understand Chef and Puppet integration patterns, and master the `null_resource` for advanced orchestration tricks.

---

## Prerequisites

- Terraform >= 1.6 installed
- AWS CLI configured
- An SSH key pair in your AWS region (`aws ec2 describe-key-pairs`)
- (For Ansible section) Ansible installed: `pip install ansible`

---

## When to Use Provisioners

| Approach                | When to Use                                              |
|-------------------------|----------------------------------------------------------|
| `user_data`             | First choice for EC2 bootstrapping (cloud-init)          |
| Packer (AMI baking)     | Pre-build images with all software installed             |
| **Provisioners**        | Last resort: legacy tools, complex multi-step setup      |

> **Important:** Provisioners are a **last resort**. They add complexity, make plans less predictable, and can cause partial failures. Prefer `user_data`, Packer AMIs, or configuration management tools called independently.

---

## Part 1 — Project Setup

### Step 1: Create project structure

```bash
mkdir -p ~/lab2.6-provisioners/{scripts,ansible,files}
cd ~/lab2.6-provisioners
```

### Step 2: Create the base configuration

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
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "key_name" {
  description = "Name of the SSH key pair in AWS"
  type        = string
}

variable "private_key_path" {
  description = "Path to the private key file for SSH"
  type        = string
  default     = "~/.ssh/id_rsa"
}

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

data "aws_vpc" "default" {
  default = true
}

# Security group allowing SSH and HTTP
resource "aws_security_group" "provisioner_sg" {
  name        = "lab26-provisioner-sg"
  description = "Allow SSH and HTTP for provisioner demos"
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
    Name = "lab26-provisioner-sg"
  }
}
```

### Step 3: Create `terraform.tfvars`

```hcl
# terraform.tfvars
key_name         = "my-key-pair"          # Replace with your key pair name
private_key_path = "~/.ssh/my-key-pair.pem"  # Replace with your key path
```

---

## Part 2 — File Provisioner

The `file` provisioner copies files or directories from the machine running Terraform to the remote resource.

### Step 4: Create files to transfer

```bash
# Create a simple web page
cat > ~/lab2.6-provisioners/files/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Provisioner Demo</title></head>
<body>
  <h1>Hello from Terraform File Provisioner!</h1>
  <p>This file was copied to the server during provisioning.</p>
</body>
</html>
EOF

# Create a config file
cat > ~/lab2.6-provisioners/files/app.conf <<'EOF'
[application]
name = demo-app
port = 8080
log_level = info
environment = development
EOF
```

### Step 5: Create `file-provisioner.tf`

```hcl
# file-provisioner.tf

resource "aws_instance" "file_demo" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.provisioner_sg.id]

  tags = {
    Name = "lab26-file-provisioner"
  }

  # Connection block defines how provisioners connect to the instance
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.private_key_path)
    host        = self.public_ip
    timeout     = "5m"
  }

  # Copy a single file
  provisioner "file" {
    source      = "${path.module}/files/index.html"
    destination = "/tmp/index.html"
  }

  # Copy a config file
  provisioner "file" {
    source      = "${path.module}/files/app.conf"
    destination = "/tmp/app.conf"
  }

  # Copy an entire directory
  provisioner "file" {
    source      = "${path.module}/files/"
    destination = "/tmp/app-files"
  }

  # Copy content directly (inline)
  provisioner "file" {
    content     = "SERVER_NAME=${self.public_ip}\nENVIRONMENT=dev\n"
    destination = "/tmp/env.conf"
  }
}

output "file_demo_public_ip" {
  value = aws_instance.file_demo.public_ip
}
```

### Step 6: Apply and verify

```bash
terraform init
terraform apply -auto-approve

# SSH into the instance and verify files
ssh -i ~/.ssh/my-key-pair.pem ec2-user@$(terraform output -raw file_demo_public_ip) \
  "ls -la /tmp/index.html /tmp/app.conf /tmp/env.conf"
```

Expected output:

```
-rw-r--r-- 1 ec2-user ec2-user 198 Jan 15 10:00 /tmp/index.html
-rw-r--r-- 1 ec2-user ec2-user  95 Jan 15 10:00 /tmp/app.conf
-rw-r--r-- 1 ec2-user ec2-user  42 Jan 15 10:00 /tmp/env.conf
```

> **Tip:** The `file` provisioner requires an SSH (or WinRM) connection. The `connection` block can be defined at the resource level (applies to all provisioners) or inside each provisioner block (applies to that provisioner only).

---

## Part 3 — `local-exec` Provisioner

The `local-exec` provisioner runs commands **on the machine where Terraform is running** (your workstation or CI server), not on the remote resource.

### Step 7: Create `local-exec-demo.tf`

```hcl
# local-exec-demo.tf

resource "aws_instance" "local_exec_demo" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.provisioner_sg.id]

  tags = {
    Name = "lab26-local-exec"
  }

  # Run a command on your LOCAL machine after instance creation
  provisioner "local-exec" {
    command = "echo 'Instance ${self.id} created with IP ${self.public_ip}' >> instance_log.txt"
  }

  # Write instance details to a file
  provisioner "local-exec" {
    command = <<-EOT
      echo '{"instance_id": "${self.id}", "public_ip": "${self.public_ip}", "created_at": "'$(date -Iseconds)'"}' >> instances.json
    EOT
  }

  # Run a script with specific interpreter
  provisioner "local-exec" {
    command     = "echo $INSTANCE_IP > /tmp/last_created_ip.txt"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      INSTANCE_IP = self.public_ip
    }
  }

  # Wait for SSH to be ready (common pattern)
  provisioner "local-exec" {
    command = <<-EOT
      for i in $(seq 1 30); do
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
          -i ${var.private_key_path} \
          ec2-user@${self.public_ip} "echo 'SSH ready'" && break
        echo "Waiting for SSH... attempt $i"
        sleep 10
      done
    EOT
  }

  # Execute a local script
  provisioner "local-exec" {
    command     = "${path.module}/scripts/post-create.sh"
    interpreter = ["/bin/bash"]
    environment = {
      INSTANCE_ID = self.id
      PUBLIC_IP   = self.public_ip
      REGION      = var.aws_region
    }
  }
}

output "local_exec_public_ip" {
  value = aws_instance.local_exec_demo.public_ip
}
```

### Step 8: Create the local script

```bash
cat > ~/lab2.6-provisioners/scripts/post-create.sh <<'SCRIPT'
#!/bin/bash
echo "========================================"
echo "Post-Create Hook"
echo "Instance ID: $INSTANCE_ID"
echo "Public IP:   $PUBLIC_IP"
echo "Region:      $REGION"
echo "Timestamp:   $(date)"
echo "========================================"

# Example: Register the instance in a CMDB or monitoring system
# curl -X POST https://cmdb.example.com/api/instances \
#   -H "Content-Type: application/json" \
#   -d "{\"id\": \"$INSTANCE_ID\", \"ip\": \"$PUBLIC_IP\"}"

echo "Post-creation tasks complete."
SCRIPT
chmod +x ~/lab2.6-provisioners/scripts/post-create.sh
```

### Step 9: Apply and check local output

```bash
terraform apply -auto-approve

# Check the local log file
cat instance_log.txt
cat instances.json
```

---

## Part 4 — `remote-exec` Provisioner

The `remote-exec` provisioner runs commands **on the remote resource** via SSH or WinRM.

### Step 10: Create `remote-exec-demo.tf`

```hcl
# remote-exec-demo.tf

resource "aws_instance" "remote_exec_demo" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.provisioner_sg.id]

  tags = {
    Name = "lab26-remote-exec"
  }

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.private_key_path)
    host        = self.public_ip
    timeout     = "5m"
  }

  # Inline commands (run in order)
  provisioner "remote-exec" {
    inline = [
      "echo 'Starting server setup...'",
      "sudo yum update -y",
      "sudo yum install -y httpd",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
      "echo '<h1>Hello from ${self.public_ip}</h1>' | sudo tee /var/www/html/index.html",
      "echo 'Server setup complete!'",
    ]
  }

  # Upload a script first, then execute it
  provisioner "file" {
    source      = "${path.module}/scripts/setup-app.sh"
    destination = "/tmp/setup-app.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup-app.sh",
      "sudo /tmp/setup-app.sh",
    ]
  }
}

output "remote_exec_public_ip" {
  value = aws_instance.remote_exec_demo.public_ip
}

output "remote_exec_url" {
  value = "http://${aws_instance.remote_exec_demo.public_ip}"
}
```

### Step 11: Create the remote setup script

```bash
cat > ~/lab2.6-provisioners/scripts/setup-app.sh <<'SCRIPT'
#!/bin/bash
set -e

echo "=== Application Setup Script ==="

# Install additional packages
yum install -y jq curl wget

# Create application directory
mkdir -p /opt/app
cat > /opt/app/config.json <<EOF
{
  "app_name": "demo-application",
  "version": "1.0.0",
  "port": 8080,
  "log_level": "info"
}
EOF

# Create a health check endpoint
cat > /var/www/html/health <<EOF
{"status": "healthy", "hostname": "$(hostname)", "timestamp": "$(date -Iseconds)"}
EOF

echo "=== Setup Complete ==="
SCRIPT
```

### Step 12: Apply and test

```bash
terraform apply -auto-approve

# Test the web server
curl http://$(terraform output -raw remote_exec_public_ip)
curl http://$(terraform output -raw remote_exec_public_ip)/health
```

Expected output:

```
<h1>Hello from 54.123.45.67</h1>
{"status": "healthy", "hostname": "ip-172-31-45-67", "timestamp": "2024-01-15T10:30:00+00:00"}
```

---

## Part 5 — Ansible Integration via `local-exec`

The most common way to integrate Terraform with Ansible is to use `local-exec` to call an Ansible playbook after instance creation.

### Step 13: Create an Ansible playbook

```bash
cat > ~/lab2.6-provisioners/ansible/playbook.yml <<'PLAYBOOK'
---
- name: Configure Web Server
  hosts: all
  become: true

  vars:
    app_name: "terraform-ansible-demo"
    http_port: 80

  tasks:
    - name: Install required packages
      yum:
        name:
          - httpd
          - php
          - php-mysqlnd
        state: present

    - name: Start and enable Apache
      systemd:
        name: httpd
        state: started
        enabled: true

    - name: Create application page
      copy:
        content: |
          <!DOCTYPE html>
          <html>
          <head><title>{{ app_name }}</title></head>
          <body>
            <h1>{{ app_name }}</h1>
            <p>Deployed by Terraform + Ansible</p>
            <p>Hostname: {{ ansible_hostname }}</p>
            <p>IP: {{ ansible_default_ipv4.address }}</p>
          </body>
          </html>
        dest: /var/www/html/index.html
        owner: apache
        group: apache
        mode: '0644'

    - name: Configure firewall for HTTP
      firewalld:
        service: http
        permanent: true
        state: enabled
        immediate: true
      ignore_errors: true

    - name: Create health check endpoint
      copy:
        content: '{"status":"ok","app":"{{ app_name }}"}'
        dest: /var/www/html/health.json
        owner: apache
        group: apache
        mode: '0644'
PLAYBOOK
```

### Step 14: Create `ansible-integration.tf`

```hcl
# ansible-integration.tf

resource "aws_instance" "ansible_managed" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.provisioner_sg.id]

  tags = {
    Name = "lab26-ansible-managed"
  }

  # Wait for the instance to be SSH-ready, then run Ansible
  provisioner "local-exec" {
    command = <<-EOT
      # Wait for SSH
      for i in $(seq 1 30); do
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
          -i ${var.private_key_path} ec2-user@${self.public_ip} \
          "echo ready" 2>/dev/null && break
        echo "Waiting for SSH... ($i/30)"
        sleep 10
      done

      # Run Ansible playbook
      ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
        -i '${self.public_ip},' \
        -u ec2-user \
        --private-key ${var.private_key_path} \
        ${path.module}/ansible/playbook.yml
    EOT
  }
}

# Alternative: Generate a dynamic inventory file
resource "local_file" "ansible_inventory" {
  content = <<-EOT
    [web_servers]
    ${aws_instance.ansible_managed.public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=${var.private_key_path}

    [web_servers:vars]
    ansible_ssh_common_args='-o StrictHostKeyChecking=no'
  EOT
  filename = "${path.module}/ansible/inventory.ini"
}

output "ansible_managed_ip" {
  value = aws_instance.ansible_managed.public_ip
}

output "ansible_command" {
  description = "Command to re-run Ansible manually"
  value       = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ${path.module}/ansible/inventory.ini ${path.module}/ansible/playbook.yml"
}
```

### Step 15: Apply with Ansible

```bash
terraform apply -auto-approve

# The Ansible playbook runs automatically after instance creation
# You can re-run it manually using the output command:
eval $(terraform output -raw ansible_command)
```

---

## Part 6 — Chef and Puppet Integration Overview

While full Chef/Puppet labs require their respective servers, here is how integration works:

### Chef Integration Pattern

```hcl
# Chef integration (conceptual example)
resource "aws_instance" "chef_managed" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  key_name      = var.key_name

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.private_key_path)
    host        = self.public_ip
  }

  # Bootstrap Chef client
  provisioner "remote-exec" {
    inline = [
      "curl -L https://omnitruck.chef.io/install.sh | sudo bash",
      "sudo mkdir -p /etc/chef",
    ]
  }

  # Copy Chef configuration
  provisioner "file" {
    source      = "chef/client.rb"
    destination = "/etc/chef/client.rb"
  }

  # Copy validation key
  provisioner "file" {
    source      = "chef/validation.pem"
    destination = "/etc/chef/validation.pem"
  }

  # Run Chef client
  provisioner "remote-exec" {
    inline = [
      "sudo chef-client -r 'role[webserver]'",
    ]
  }

  tags = { Name = "chef-managed" }
}
```

### Puppet Integration Pattern

```hcl
# Puppet integration (conceptual example)
resource "aws_instance" "puppet_managed" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  key_name      = var.key_name

  # Use user_data for Puppet agent installation
  user_data = <<-EOF
    #!/bin/bash
    rpm -Uvh https://yum.puppet.com/puppet7-release-el-8.noarch.rpm
    yum install -y puppet-agent
    /opt/puppetlabs/bin/puppet config set server puppet.example.com
    /opt/puppetlabs/bin/puppet agent --test --waitforcert 60
  EOF

  tags = { Name = "puppet-managed" }
}
```

> **Note:** In modern practice, Packer is preferred for baking Chef/Puppet runs into AMIs. This avoids provisioner complexity and makes instance launch faster and more reliable.

---

## Part 7 — `null_resource` and Triggers

The `null_resource` is a resource that does nothing by itself but can run provisioners. Combined with `triggers`, it enables powerful orchestration patterns.

### Step 16: Create `null-resource-demo.tf`

```hcl
# null-resource-demo.tf

# --- Basic null_resource with trigger ---
variable "app_version" {
  description = "Application version to deploy"
  type        = string
  default     = "1.0.0"
}

# This re-runs whenever app_version changes
resource "null_resource" "app_deploy" {
  triggers = {
    app_version = var.app_version
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Deploying application version ${var.app_version}"
      echo "Deploy timestamp: $(date -Iseconds)"
      echo "Version ${var.app_version} deployed at $(date)" >> deploy_log.txt
    EOT
  }
}

# --- Trigger on file content change ---
resource "null_resource" "config_update" {
  triggers = {
    config_hash = filemd5("${path.module}/files/app.conf")
  }

  provisioner "local-exec" {
    command = "echo 'Configuration changed! Hash: ${self.triggers.config_hash}'"
  }
}

# --- Trigger on another resource change ---
resource "null_resource" "post_sg_update" {
  triggers = {
    sg_id = aws_security_group.provisioner_sg.id
  }

  provisioner "local-exec" {
    command = "echo 'Security group updated: ${aws_security_group.provisioner_sg.id}'"
  }
}

# --- Always run (trigger on timestamp) ---
resource "null_resource" "always_run" {
  triggers = {
    always = timestamp()
  }

  provisioner "local-exec" {
    command = "echo 'This runs on every apply: $(date)'"
  }
}

# --- Dependency orchestration ---
# Use null_resource to create explicit ordering points
resource "null_resource" "wait_for_instances" {
  depends_on = [
    aws_instance.file_demo,
    aws_instance.remote_exec_demo,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "All instances are ready!"
      echo "File demo:   ${aws_instance.file_demo.public_ip}"
      echo "Remote exec: ${aws_instance.remote_exec_demo.public_ip}"
    EOT
  }
}

# --- Destroy-time provisioner ---
resource "null_resource" "cleanup" {
  triggers = {
    sg_id = aws_security_group.provisioner_sg.id
  }

  # This runs when the null_resource is DESTROYED
  provisioner "local-exec" {
    when    = destroy
    command = "echo 'Cleanup: deregistering resources from monitoring...'"
  }

  # This runs on create (default behavior)
  provisioner "local-exec" {
    command = "echo 'Setup: registering resources in monitoring...'"
  }
}
```

### Step 17: Test null_resource triggers

```bash
# First apply
terraform apply -auto-approve
# Output: "Deploying application version 1.0.0"

# Change the version and apply again
terraform apply -var 'app_version=2.0.0' -auto-approve
# Output: "Deploying application version 2.0.0"
# Only the null_resource.app_deploy is replaced -- other resources are unchanged

# Check the deploy log
cat deploy_log.txt
```

Expected:

```
Version 1.0.0 deployed at Mon Jan 15 10:00:00 UTC 2024
Version 2.0.0 deployed at Mon Jan 15 10:05:00 UTC 2024
```

### Step 18: Test destroy-time provisioner

```bash
terraform destroy -target=null_resource.cleanup
```

Expected output:

```
null_resource.cleanup: Destroying... [id=1234567890]
null_resource.cleanup (local-exec): Executing: ["/bin/sh" "-c" "echo 'Cleanup: deregistering resources from monitoring...'"]
null_resource.cleanup (local-exec): Cleanup: deregistering resources from monitoring...
null_resource.cleanup: Destruction complete after 0s
```

> **Important:** Destroy-time provisioners can only reference `self` and cannot access other resources. They also cannot use `connection` blocks that reference other resources. Keep destroy-time provisioners simple and self-contained.

---

## Part 8 — Third-Party Plugins Overview

Terraform's plugin ecosystem extends far beyond AWS. Here are commonly used third-party providers:

| Provider          | Purpose                           | Example Use Case                           |
|-------------------|-----------------------------------|--------------------------------------------|
| `hashicorp/helm`  | Deploy Helm charts to Kubernetes  | Install nginx-ingress, cert-manager        |
| `hashicorp/vault` | Manage HashiCorp Vault secrets    | Dynamic secrets, PKI certificates          |
| `datadog/datadog` | Configure Datadog monitoring      | Dashboards, monitors, SLOs                 |
| `pagerduty`       | PagerDuty incident management     | Services, escalation policies              |
| `github`          | GitHub repository management      | Repos, teams, branch protection            |
| `cloudflare`      | DNS and CDN management            | DNS records, page rules, WAF              |

Example: Using the Helm provider alongside AWS:

```hcl
# Conceptual example - deploying a Helm chart after EKS creation
provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name]
    }
  }
}

resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "ingress-nginx"

  create_namespace = true

  set {
    name  = "controller.replicaCount"
    value = "2"
  }
}
```

---

## Provisioner Failure Behavior

| Scenario                                   | Default Behavior                    | Override                     |
|--------------------------------------------|-------------------------------------|------------------------------|
| Create-time provisioner fails              | Resource marked as **tainted**      | `on_failure = continue`      |
| Destroy-time provisioner fails             | Destroy continues                   | `on_failure = fail`          |
| Tainted resource on next apply             | Destroyed and recreated             | `terraform untaint <addr>`   |

```hcl
# Override failure behavior
provisioner "remote-exec" {
  on_failure = continue  # Don't taint the resource if this fails
  inline     = ["some-command-that-might-fail || true"]
}
```

---

## Clean Up

```bash
cd ~/lab2.6-provisioners
terraform destroy -auto-approve
rm -f instance_log.txt instances.json deploy_log.txt
```

---

## Summary

| Provisioner   | Runs Where       | Common Use Case                                    |
|---------------|------------------|----------------------------------------------------|
| `file`        | Remote (via SSH) | Copy config files, scripts, certificates           |
| `local-exec`  | Local machine    | Run scripts, call Ansible, update CMDB             |
| `remote-exec` | Remote (via SSH) | Install packages, configure services               |
| `null_resource`| N/A (orchestration)| Triggers, dependency ordering, destroy-time hooks |

| Integration    | Method                                                            |
|----------------|-------------------------------------------------------------------|
| Ansible        | `local-exec` calling `ansible-playbook` with dynamic inventory    |
| Chef           | `remote-exec` to bootstrap chef-client, or Packer AMI baking     |
| Puppet         | `user_data` to install puppet-agent, or Packer AMI baking        |
| Helm           | `helm` provider (native Terraform, no provisioners needed)        |

> **Key takeaway:** Provisioners bridge the gap between infrastructure provisioning and configuration management. Use `local-exec` for Ansible integration and local automation, `remote-exec` for quick remote setup, and `null_resource` for orchestration patterns. But always ask first: can this be done with `user_data`, a pre-baked AMI, or a native Terraform provider? If yes, prefer that approach.
