# 021 — Terraform AWS ElastiCache Redis Demo

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~30 minutes (Redis cluster takes ~3-4 minutes to create)

## Topic

**AWS ElastiCache** is a fully managed in-memory caching service. This lab provisions an **ElastiCache Redis 7.1** cluster using Terraform, then connects to it from an EC2 client instance to run real Redis commands (SET, GET, KEYS, DEL, EXPIRE, TTL).

**Why managed Redis?**

| Self-managed Redis on EC2 | AWS ElastiCache Redis |
|---|---|
| You install, patch, restart Redis | AWS handles upgrades, patches |
| No automatic failover | Multi-AZ failover available |
| You monitor disk/memory manually | CloudWatch metrics built in |
| Backup is manual | Automatic snapshot support |

Key Terraform resources introduced in this lab:

- `aws_elasticache_cluster` — provisions the Redis cluster
- `aws_elasticache_subnet_group` — tells ElastiCache which subnets to use
- `cache_nodes[0].address` — the endpoint attribute for the cluster node
- `user_data` — bootstraps the EC2 client with `redis-tools` at launch

---

## Architecture

ElastiCache Redis lives **inside the VPC only** — it has no public IP and cannot be reached from the internet. To run `redis-cli` commands, you need a machine inside the same VPC. This lab creates an EC2 instance in the default VPC to serve as the Redis client.

```text
  ┌──────────────────────────────────────────────────────────────┐
  │  Your GCE VM (this machine)                                  │
  │                                                              │
  │  terraform apply ──────────────────────────────────────────► │
  │                                                              │
  │  ssh -i ~/.ssh/terraform-021-demo ubuntu@CLIENT_IP ────────► │
  └──────────────────────────────────────────────────────────────┘
                           │
                           │  SSH (port 22, public internet)
                           ▼
  ┌─────────────────────────────────────────────────────────────────────────┐
  │  AWS VPC (default VPC, ap-south-1)                                      │
  │                                                                         │
  │  ┌──────────────────────────┐        ┌───────────────────────────────┐  │
  │  │  EC2 t3.micro            │        │  ElastiCache Redis 7.1        │  │
  │  │  terraform-021-redis-    │        │  terraform-021-redis          │  │
  │  │  client                  │        │                               │  │
  │  │  IP: 65.1.84.131         │        │  cache.t3.micro, port 6379   │  │
  │  │  (ubuntu, redis-tools)   │──────► │  VPC-internal endpoint only  │  │
  │  └──────────────────────────┘        └───────────────────────────────┘  │
  │       sg: terraform-021-ssh-sg            sg: terraform-021-redis-sg    │
  │       (port 22 inbound)                   (port 6379 inbound)           │
  └─────────────────────────────────────────────────────────────────────────┘
```

**Why the EC2 client is required:**
ElastiCache endpoints are VPC-internal DNS names — they resolve only within the VPC. Running `redis-cli` directly from your GCE VM would fail because the endpoint is unreachable from outside AWS. The EC2 client instance is inside the same VPC, so it can reach the Redis cluster on port 6379.

---

## What Terraform Creates

```text
tls_private_key.demo              → generates ED25519 key pair in memory
local_sensitive_file.private_key  → writes private key to ~/.ssh/terraform-021-demo (0600)
aws_key_pair.demo                 → uploads public key to AWS
aws_security_group.ssh            → allows SSH on port 22 (for EC2 client)
aws_security_group.redis          → allows Redis on port 6379 (for ElastiCache)
aws_elasticache_subnet_group.demo → registers default subnets with ElastiCache
aws_elasticache_cluster.redis     → Redis 7.1 cluster (cache.t3.micro, 1 node)
aws_instance.redis_client         → Ubuntu 22.04 EC2 with redis-tools pre-installed
```

**Plan: 8 to add, 0 to change, 0 to destroy.**

---

## 1. Create Project Folder

```bash
mkdir -p ~/terraform-aws-elasticache-021-demo
cd ~/terraform-aws-elasticache-021-demo
```

---

## 2. Check Your AWS Region

```bash
aws configure get region
aws sts get-caller-identity
```

Update `terraform.tfvars` to match your configured region (e.g., `ap-south-1`).

---

## 3. Create Terraform Files

Create the following files:

```text
providers.tf
variables.tf
main.tf
outputs.tf
terraform.tfvars
```

---

## 4. providers.tf

Three providers are required — AWS for infrastructure, TLS to generate the SSH key pair, and Local to save the private key file to disk.

```bash
cat > providers.tf <<'EOF_TF'
terraform {
  required_providers {
    aws   = { source = "hashicorp/aws",   version = "~> 6.0" }
    tls   = { source = "hashicorp/tls",   version = "~> 4.0" }
    local = { source = "hashicorp/local", version = "~> 2.0" }
  }
}

provider "aws" { region = var.aws_region }
EOF_TF
```

| Provider | Purpose |
|----------|---------|
| `hashicorp/aws` | Creates all AWS resources (ElastiCache, EC2, security groups) |
| `hashicorp/tls` | Generates the ED25519 SSH key pair |
| `hashicorp/local` | Saves the generated private key to `~/.ssh/terraform-021-demo` |

---

## 5. variables.tf

```bash
cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_port" {
  type    = number
  default = 6379
}

variable "private_key_path" {
  type    = string
  default = "~/.ssh/terraform-021-demo"
}
EOF_TF
```

---

## 6. main.tf

```bash
cat > main.tf <<'EOF_TF'
data "aws_vpc" "default" { default = true }

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
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

resource "tls_private_key" "demo" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.demo.private_key_openssh
  filename        = pathexpand(var.private_key_path)
  file_permission = "0600"
}

resource "aws_key_pair" "demo" {
  key_name   = "terraform-021-demo-key"
  public_key = tls_private_key.demo.public_key_openssh
}

resource "aws_security_group" "ssh" {
  name        = "terraform-021-ssh-sg"
  description = "Allow SSH"
  vpc_id      = data.aws_vpc.default.id

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

  tags = { Name = "terraform-021-ssh-sg" }
}

resource "aws_security_group" "redis" {
  name        = "terraform-021-redis-sg"
  description = "Allow Redis access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = var.redis_port
    to_port     = var.redis_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "terraform-021-redis-sg" }
}

resource "aws_elasticache_subnet_group" "demo" {
  name       = "terraform-021-redis-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "terraform-021-redis"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.1"
  port                 = var.redis_port
  subnet_group_name    = aws_elasticache_subnet_group.demo.name
  security_group_ids   = [aws_security_group.redis.id]

  tags = { Name = "terraform-021-redis" }
}

resource "aws_instance" "redis_client" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.demo.key_name
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y redis-tools
  EOF

  tags = { Name = "terraform-021-redis-client" }
}
EOF_TF
```

**Key resource connections in main.tf:**

```text
tls_private_key.demo.private_key_openssh   → local_sensitive_file.private_key (saved to disk)
tls_private_key.demo.public_key_openssh    → aws_key_pair.demo.public_key (uploaded to AWS)
aws_key_pair.demo.key_name                 → aws_instance.redis_client.key_name
aws_security_group.ssh.id                  → aws_instance.redis_client.vpc_security_group_ids
aws_security_group.redis.id                → aws_elasticache_cluster.redis.security_group_ids
aws_elasticache_subnet_group.demo.name     → aws_elasticache_cluster.redis.subnet_group_name
data.aws_ami.ubuntu.id                     → aws_instance.redis_client.ami
data.aws_subnets.default.ids               → aws_elasticache_subnet_group.demo.subnet_ids
```

**Why `user_data` on the EC2 instance?**
`user_data` is a shell script that runs once when the instance first boots. Here it runs `apt-get install -y redis-tools` so that `redis-cli` is available immediately when you SSH in — no manual installation needed.

---

## 7. outputs.tf

```bash
cat > outputs.tf <<'EOF_TF'
output "redis_endpoint" {
  description = "Redis cluster endpoint address"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  value = aws_elasticache_cluster.redis.port
}

output "client_public_ip" {
  description = "EC2 client instance public IP"
  value       = aws_instance.redis_client.public_ip
}

output "ssh_command" {
  value = "ssh -i ${pathexpand(var.private_key_path)} ubuntu@${aws_instance.redis_client.public_ip}"
}

output "redis_cli_connect" {
  description = "Run this from inside the EC2 client"
  value       = "redis-cli -h ${aws_elasticache_cluster.redis.cache_nodes[0].address} -p ${aws_elasticache_cluster.redis.port}"
}
EOF_TF
```

`cache_nodes[0].address` — ElastiCache returns a list of cache nodes (even with `num_cache_nodes = 1`). Index `[0]` accesses the first (only) node's endpoint hostname.

---

## 8. terraform.tfvars

```bash
cat > terraform.tfvars <<'EOF_TF'
aws_region       = "ap-south-1"
redis_node_type  = "cache.t3.micro"
redis_port       = 6379
private_key_path = "~/.ssh/terraform-021-demo"
EOF_TF
```

Update `aws_region` to match your configured region (`aws configure get region`).

---

## 9. Initialize Terraform

```bash
terraform init
```

Expected output:

```text
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

---

## 10. Format and Validate

```bash
terraform fmt
terraform validate
```

Expected:

```text
Success! The configuration is valid.
```

---

## 11. Plan

```bash
terraform plan
```

Expected plan summary:

```text
# tls_private_key.demo will be created
# local_sensitive_file.private_key will be created
# aws_key_pair.demo will be created
# aws_security_group.ssh will be created
# aws_security_group.redis will be created
# aws_elasticache_subnet_group.demo will be created
# aws_elasticache_cluster.redis will be created
# aws_instance.redis_client will be created

Plan: 8 to add, 0 to change, 0 to destroy.
```

Note the `aws_elasticache_cluster` entry in the plan will show:

```text
+ cluster_id           = "terraform-021-redis"
+ engine               = "redis"
+ engine_version       = "7.1"
+ node_type            = "cache.t3.micro"
+ num_cache_nodes      = 1
+ parameter_group_name = "default.redis7"
+ port                 = 6379
```

---

## 12. Apply

```bash
terraform apply
```

Type `yes` when prompted.

**Important:** `aws_elasticache_cluster` takes **3-4 minutes** to provision. Terraform shows a creation timer while it waits:

```text
tls_private_key.demo: Creating...
tls_private_key.demo: Creation complete after 0s

local_sensitive_file.private_key: Creating...
local_sensitive_file.private_key: Creation complete after 0s

aws_key_pair.demo: Creating...
aws_security_group.ssh: Creating...
aws_security_group.redis: Creating...

aws_key_pair.demo: Creation complete after 0s
aws_security_group.ssh: Creation complete after 2s
aws_security_group.redis: Creation complete after 2s

aws_elasticache_subnet_group.demo: Creating...
aws_elasticache_subnet_group.demo: Creation complete after 1s

aws_elasticache_cluster.redis: Creating...
aws_instance.redis_client: Creating...
aws_instance.redis_client: Creation complete after 13s [id=i-0dfe1f29c237a03e3]
aws_elasticache_cluster.redis: Still creating... [10s elapsed]
aws_elasticache_cluster.redis: Still creating... [1m0s elapsed]
aws_elasticache_cluster.redis: Still creating... [2m0s elapsed]
aws_elasticache_cluster.redis: Still creating... [3m0s elapsed]
aws_elasticache_cluster.redis: Creation complete after 3m42s [id=terraform-021-redis]

Apply complete! Resources: 8 added, 0 changed, 0 destroyed.
```

**Creation order:**

1. `tls_private_key` — no dependencies, created first
2. `local_sensitive_file` and `aws_key_pair` — wait for private key
3. `aws_security_group.ssh` and `aws_security_group.redis` — run in parallel (no dependencies on each other)
4. `aws_elasticache_subnet_group` — waits for subnet data source (resolved at plan time)
5. `aws_instance.redis_client` — waits for key pair and SSH security group
6. `aws_elasticache_cluster` — waits for subnet group and Redis security group; takes the longest

---

## 13. Post-Apply Outputs

After apply completes, Terraform prints outputs automatically:

```text
Outputs:

client_public_ip  = "65.1.84.131"
redis_cli_connect = "redis-cli -h terraform-021-redis.kv4kz2.0001.aps1.cache.amazonaws.com -p 6379"
redis_endpoint    = "terraform-021-redis.kv4kz2.0001.aps1.cache.amazonaws.com"
redis_port        = 6379
ssh_command       = "ssh -i /home/USER/.ssh/terraform-021-demo ubuntu@65.1.84.131"
```

To retrieve outputs again at any time:

```bash
terraform output
terraform output -raw redis_endpoint
terraform output -raw ssh_command
terraform output -raw redis_cli_connect
```

---

## 14. SSH into the EC2 Client

```bash
# Get the SSH command from outputs and run it directly
$(terraform output -raw ssh_command)
```

Or explicitly:

```bash
ssh -i ~/.ssh/terraform-021-demo ubuntu@65.1.84.131
```

When prompted about host fingerprint, type `yes`.

**Wait ~60 seconds after apply** before SSHing in — `user_data` runs in the background on first boot and needs time to install `redis-tools`. If `redis-cli` is not yet found, wait a moment and try again.

Verify `redis-cli` is installed inside the EC2 client:

```bash
redis-cli --version
# redis-cli 6.0.16
```

---

## 15. Connect to Redis and Run Commands

Inside the EC2 client, connect to the Redis cluster using the endpoint from the outputs:

```bash
redis-cli -h terraform-021-redis.kv4kz2.0001.aps1.cache.amazonaws.com -p 6379
```

Or use the output directly:

```bash
# From your GCE VM, SSH to EC2 client first, then inside EC2 client:
REDIS_HOST=$(terraform output -raw redis_endpoint)
redis-cli -h $REDIS_HOST -p 6379
```

You will see the Redis prompt:

```text
terraform-021-redis.kv4kz2.0001.aps1.cache.amazonaws.com:6379>
```

Run these commands inside the Redis interactive session:

```bash
# Test connectivity
PING
# Output: PONG

# Store key-value pairs
SET course "terraform-4days"
# Output: OK

SET author "saravanans"
# Output: OK

SET site "robochef.co"
# Output: OK

SET company "chillbotindia"
# Output: OK

SET platform "chillbotindia.com"
# Output: OK

# Retrieve values
GET course
# Output: "terraform-4days"

GET author
# Output: "saravanans"

GET site
# Output: "robochef.co"

GET company
# Output: "chillbotindia"

# List all keys
KEYS *
# Output:
# 1) "course"
# 2) "site"
# 3) "author"
# 4) "company"
# 5) "platform"

# Delete a key
DEL course
# Output: (integer) 1

# Check if a key exists
EXISTS course
# Output: (integer) 0   (0 = does not exist)

EXISTS author
# Output: (integer) 1   (1 = exists)

# Check TTL (time to live) — -1 means no expiry set
TTL author
# Output: (integer) -1

# Set an expiry of 60 seconds on the author key
EXPIRE author 60
# Output: (integer) 1

# Confirm TTL is now counting down
TTL author
# Output: (integer) 58  (or similar, counting down)

# Exit the Redis session
exit
```

---

## 16. One-Liner Redis Commands (No Interactive Session)

You can also run individual Redis commands without entering the interactive session:

```bash
# From inside the EC2 client:
REDIS_HOST="terraform-021-redis.kv4kz2.0001.aps1.cache.amazonaws.com"

redis-cli -h $REDIS_HOST -p 6379 PING
# PONG

redis-cli -h $REDIS_HOST -p 6379 SET env "production"
# OK

redis-cli -h $REDIS_HOST -p 6379 GET env
# "production"

redis-cli -h $REDIS_HOST -p 6379 KEYS "*"
# (lists all keys)

redis-cli -h $REDIS_HOST -p 6379 SET owner "saravanans"
# OK

redis-cli -h $REDIS_HOST -p 6379 GET owner
# "saravanans"
```

This pattern is useful in scripts and automation where you send a single command and capture the output without opening an interactive session.

---

## 17. Exit EC2 Client and Return to GCE VM

```bash
exit
# Connection to 65.1.84.131 closed.
```

You are now back on your GCE VM.

---

## 18. Destroy Resources

After the demo, destroy all AWS resources:

```bash
terraform destroy
```

Type `yes` when prompted.

**Important:** The security group deletion takes approximately **1 minute 18 seconds** after the ElastiCache cluster signals that it is stopping. Terraform waits for ElastiCache to fully de-register from the security group before it can delete the group. This is normal:

```text
aws_elasticache_cluster.redis: Destroying... [id=terraform-021-redis]
aws_elasticache_cluster.redis: Still destroying... [1m0s elapsed]
aws_elasticache_cluster.redis: Destruction complete after 1m22s

aws_security_group.redis: Destroying... [id=sg-xxxxxxxxxx]
aws_elasticache_subnet_group.demo: Destroying... [id=terraform-021-redis-subnet-group]
aws_security_group.redis: Destruction complete after 56s
aws_elasticache_subnet_group.demo: Destruction complete after 0s

aws_instance.redis_client: Destroying...
aws_instance.redis_client: Still destroying... [30s elapsed]
aws_instance.redis_client: Destruction complete after 40s

aws_key_pair.demo: Destroying...
aws_security_group.ssh: Destroying...
aws_key_pair.demo: Destruction complete after 0s
aws_security_group.ssh: Destruction complete after 1s

local_sensitive_file.private_key: Destroying...
local_sensitive_file.private_key: Destruction complete after 0s

tls_private_key.demo: Destroying...
tls_private_key.demo: Destruction complete after 0s

Destroy complete! Resources: 8 destroyed.
```

After destroy, clean up the `.terraform` provider cache:

```bash
rm -rf .terraform
```

---

## 19. Cost Warning

`cache.t3.micro` is **NOT in the AWS Free Tier**.

| Resource | Approximate Cost |
|---|---|
| `cache.t3.micro` Redis node | ~$0.016 per hour |
| `t3.micro` EC2 instance | Free tier eligible (750 hrs/month) |

**Destroy immediately after the demo.** Even 1 hour of an accidental overnight run costs approximately $0.016. Always confirm with `terraform destroy` before closing your terminal.

---

## 20. Live-Tested Results

This lab was run live on `2026-05-21` in `ap-south-1`. Verified results:

| Item | Actual Value |
|---|---|
| Redis cluster ID | `terraform-021-redis` |
| Redis endpoint | `terraform-021-redis.kv4kz2.0001.aps1.cache.amazonaws.com` |
| Redis engine version | `7.1` |
| Node type | `cache.t3.micro` |
| Port | `6379` |
| EC2 client instance ID | `i-0dfe1f29c237a03e3` |
| EC2 client public IP | `65.1.84.131` |
| PING response | `PONG` |
| SET course "terraform-4days" | `OK` |
| SET author "saravanans" | `OK` |
| SET site "robochef.co" | `OK` |
| GET course | `"terraform-4days"` |
| GET author | `"saravanans"` |
| KEYS "*" | `course`, `site`, `author` |
| Resources created | 8 |
| Resources destroyed | 8 |
| SG deletion wait time | ~1m18s (waiting for ElastiCache to fully stop) |

---

## 21. Full Copy-Paste Setup Script

```bash
mkdir -p ~/terraform-aws-elasticache-021-demo
cd ~/terraform-aws-elasticache-021-demo

cat > providers.tf <<'EOF_TF'
terraform {
  required_providers {
    aws   = { source = "hashicorp/aws",   version = "~> 6.0" }
    tls   = { source = "hashicorp/tls",   version = "~> 4.0" }
    local = { source = "hashicorp/local", version = "~> 2.0" }
  }
}

provider "aws" { region = var.aws_region }
EOF_TF

cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_port" {
  type    = number
  default = 6379
}

variable "private_key_path" {
  type    = string
  default = "~/.ssh/terraform-021-demo"
}
EOF_TF

cat > main.tf <<'EOF_TF'
data "aws_vpc" "default" { default = true }

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
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

resource "tls_private_key" "demo" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.demo.private_key_openssh
  filename        = pathexpand(var.private_key_path)
  file_permission = "0600"
}

resource "aws_key_pair" "demo" {
  key_name   = "terraform-021-demo-key"
  public_key = tls_private_key.demo.public_key_openssh
}

resource "aws_security_group" "ssh" {
  name        = "terraform-021-ssh-sg"
  description = "Allow SSH"
  vpc_id      = data.aws_vpc.default.id

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

  tags = { Name = "terraform-021-ssh-sg" }
}

resource "aws_security_group" "redis" {
  name        = "terraform-021-redis-sg"
  description = "Allow Redis access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = var.redis_port
    to_port     = var.redis_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "terraform-021-redis-sg" }
}

resource "aws_elasticache_subnet_group" "demo" {
  name       = "terraform-021-redis-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "terraform-021-redis"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.1"
  port                 = var.redis_port
  subnet_group_name    = aws_elasticache_subnet_group.demo.name
  security_group_ids   = [aws_security_group.redis.id]

  tags = { Name = "terraform-021-redis" }
}

resource "aws_instance" "redis_client" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.demo.key_name
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y redis-tools
  EOF

  tags = { Name = "terraform-021-redis-client" }
}
EOF_TF

cat > outputs.tf <<'EOF_TF'
output "redis_endpoint" {
  description = "Redis cluster endpoint address"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  value = aws_elasticache_cluster.redis.port
}

output "client_public_ip" {
  description = "EC2 client instance public IP"
  value       = aws_instance.redis_client.public_ip
}

output "ssh_command" {
  value = "ssh -i ${pathexpand(var.private_key_path)} ubuntu@${aws_instance.redis_client.public_ip}"
}

output "redis_cli_connect" {
  description = "Run this from inside the EC2 client"
  value       = "redis-cli -h ${aws_elasticache_cluster.redis.cache_nodes[0].address} -p ${aws_elasticache_cluster.redis.port}"
}
EOF_TF

cat > terraform.tfvars <<'EOF_TF'
aws_region       = "ap-south-1"
redis_node_type  = "cache.t3.micro"
redis_port       = 6379
private_key_path = "~/.ssh/terraform-021-demo"
EOF_TF

terraform init
terraform fmt
terraform validate
terraform plan
```

Then apply:

```bash
terraform apply
# Wait ~3-4 minutes for aws_elasticache_cluster to provision
```

SSH into the EC2 client (wait ~60s after apply for user_data to finish):

```bash
ssh -i ~/.ssh/terraform-021-demo ubuntu@$(terraform output -raw client_public_ip)
```

Inside EC2 client:

```bash
redis-cli -h $(terraform output -raw redis_endpoint 2>/dev/null || echo "REDIS_HOST") -p 6379
# PING → PONG
# SET author "saravanans" → OK
# SET site "robochef.co" → OK
# SET company "chillbotindia" → OK
# GET author → "saravanans"
# KEYS * → (all keys)
# exit
```

Destroy:

```bash
terraform destroy
rm -rf .terraform
```

---

## 22. Final File Structure

```text
terraform-aws-elasticache-021-demo/
├── main.tf
├── outputs.tf
├── providers.tf
├── terraform.tfvars
├── variables.tf
├── .terraform.lock.hcl
├── terraform.tfstate
└── terraform.tfstate.backup

Private key (outside project folder):
~/.ssh/terraform-021-demo       ← created by Terraform on apply, deleted on destroy
```

---

## 23. Concept Summary

| Resource / Concept | What It Does |
|---|---|
| `aws_elasticache_cluster` | Provisions the managed Redis cluster. Engine, version, node type, and port are all specified here. |
| `aws_elasticache_subnet_group` | Groups the VPC subnets that ElastiCache is allowed to use. Required before creating a cluster. |
| `cache_nodes[0].address` | The DNS endpoint of the first (and only) Redis node. Used in `redis-cli -h`. |
| `engine_version = "7.1"` | Specifies the Redis engine version. `parameter_group_name` must match (e.g., `default.redis7`). |
| `parameter_group_name` | Controls Redis runtime settings. Use `default.redis7` for Redis 7.x with default settings. |
| `user_data` | Shell script that runs on EC2 first boot. Used here to install `redis-tools` automatically. |
| `num_cache_nodes = 1` | A single-node Redis cluster (no replication). Sufficient for demos and development. |
| `aws_security_group.redis` | Must allow inbound TCP port 6379 from the EC2 client's VPC CIDR or security group. |
| EC2 client in same VPC | ElastiCache endpoints are VPC-internal only. An EC2 instance in the same VPC is required to reach them. |
| SG deletion delay on destroy | Terraform waits ~1-2 minutes for ElastiCache to fully de-register from the security group before deleting it. |
| `cache.t3.micro` cost | ~$0.016/hr — NOT free tier. Always destroy immediately after the demo. |
