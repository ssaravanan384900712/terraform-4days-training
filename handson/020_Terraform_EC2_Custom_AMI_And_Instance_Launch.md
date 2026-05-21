# 020 — EC2 Instance Modification via SSH, Custom AMI Creation, and New Instance Launch

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~35 minutes (AMI creation takes ~3-4 minutes)

---

## Topic

A **custom AMI (Amazon Machine Image)** is a snapshot of an EC2 instance — OS, installed packages, config files, and all. Once captured, you can launch any number of identical instances from that image.

This is the **golden image pattern**:

```text
Base EC2 instance
  → SSH in → install software, configure system
  → Snapshot to AMI (aws_ami_from_instance)
  → Launch N identical instances from that AMI
```

Why it matters:

- **Consistency** — every instance starts from the exact same known state
- **Speed** — no boot-time provisioning scripts needed; software is pre-baked
- **Immutability** — to update, bake a new AMI and replace instances
- **Compliance** — hardened AMIs can be audited once and reused many times

In this lab, you will:

1. Launch a base EC2 instance (Phase 1, via `-target`)
2. SSH in and install nginx + write a custom HTML file
3. Tell Terraform to snapshot that instance into a custom AMI and launch a second instance from it (Phase 2, full apply)
4. Verify the second instance inherited everything from the base
5. Destroy all resources cleanly

**Live test results (ap-south-1, 2026-05-21):**

| Item | Value |
|---|---|
| Base instance ID | `i-07225665a4cd1ed8b` |
| Base instance IP | `13.207.57.13` |
| Custom AMI ID | `ami-0e1ee1ef58f2e3444` |
| AMI creation time | ~3m6s |
| New instance ID | `i-07003f9d8ef591767` |
| New instance IP | `3.6.91.95` |
| Resources destroyed | 7 (tls_key, local_file, key_pair, sg, base_instance, AMI, from_ami_instance) |

---

## What Terraform Creates

```text
Phase 1 (targeted apply)
  tls_private_key.demo          → generates ED25519 key pair in memory
  local_sensitive_file.private_key → writes private key to ~/.ssh/terraform-020-demo
  aws_key_pair.demo             → uploads public key to AWS
  aws_security_group.ssh        → allows SSH on port 22
  aws_instance.base             → Ubuntu 22.04 base EC2 instance

  ← SSH here and install nginx + custom.html →

Phase 2 (full apply)
  aws_ami_from_instance.custom  → snapshots base instance → custom AMI
  aws_instance.from_ami         → new EC2 launched from the custom AMI
```

**Plan summary across both phases: 7 to add, 0 to change, 0 to destroy.**

---

## Project Files

```text
terraform-aws-ec2-020-demo/
├── providers.tf       ← aws, tls, local providers
├── variables.tf       ← region, instance_type, private_key_path
├── main.tf            ← tls key, local file, aws_key_pair, sg, base instance
├── ami.tf             ← aws_ami_from_instance + new instance (Phase 2)
├── outputs.tf         ← IPs, IDs, SSH commands
└── terraform.tfvars   ← ap-south-1 overrides
```

---

## 1. Create Project Folder

```bash
mkdir -p ~/terraform-aws-ec2-020-demo
cd ~/terraform-aws-ec2-020-demo
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

### providers.tf

Three providers are required — `aws` for EC2/AMI, `tls` to generate the SSH key, `local` to save it to disk.

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
|---|---|
| `hashicorp/aws` | Creates EC2 instances, key pair, security group, AMI |
| `hashicorp/tls` | Generates the ED25519 SSH key pair inside Terraform |
| `hashicorp/local` | Saves the private key file to disk with `0600` permissions |

---

### variables.tf

```bash
cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "private_key_path" {
  type    = string
  default = "~/.ssh/terraform-020-demo"
}
EOF_TF
```

---

### main.tf

Contains the base infrastructure: SSH key generation, key pair, security group, and the base EC2 instance that you will modify before snapshotting.

```bash
cat > main.tf <<'EOF_TF'
resource "tls_private_key" "demo" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.demo.private_key_openssh
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

resource "aws_key_pair" "demo" {
  key_name   = "terraform-020-demo-key"
  public_key = tls_private_key.demo.public_key_openssh
}

resource "aws_security_group" "ssh" {
  name        = "terraform-020-ssh-sg"
  description = "Allow SSH"

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

  tags = { Name = "terraform-020-ssh-sg" }
}

resource "aws_instance" "base" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.demo.key_name
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  associate_public_ip_address = true

  tags = { Name = "terraform-020-base" }
}
EOF_TF
```

**Key connections in main.tf:**

```text
tls_private_key.demo.private_key_openssh  → local_sensitive_file (saved to disk)
tls_private_key.demo.public_key_openssh   → aws_key_pair.demo.public_key
aws_key_pair.demo.key_name                → aws_instance.base.key_name
aws_security_group.ssh.id                 → aws_instance.base.vpc_security_group_ids
data.aws_ami.ubuntu.id                    → aws_instance.base.ami
```

---

### ami.tf

This file is kept **separate** from `main.tf` on purpose. You do not want Terraform to try creating the AMI until after you have made changes to the base instance via SSH. Keeping it in its own file makes the two-phase workflow clearer.

```bash
cat > ami.tf <<'EOF_TF'
resource "aws_ami_from_instance" "custom" {
  name                    = "terraform-020-custom-ami"
  source_instance_id      = aws_instance.base.id
  snapshot_without_reboot = false

  tags = { Name = "terraform-020-custom-ami" }
}

resource "aws_instance" "from_ami" {
  ami                         = aws_ami_from_instance.custom.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.demo.key_name
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  associate_public_ip_address = true

  tags = { Name = "terraform-020-from-custom-ami" }
}
EOF_TF
```

---

### outputs.tf

```bash
cat > outputs.tf <<'EOF_TF'
output "base_instance_ip" { value = aws_instance.base.public_ip }
output "base_instance_id" { value = aws_instance.base.id }
output "ssh_command_base" { value = "ssh -i ${pathexpand(var.private_key_path)} ubuntu@${aws_instance.base.public_ip}" }
output "custom_ami_id"    { value = aws_ami_from_instance.custom.id }
output "new_instance_ip"  { value = aws_instance.from_ami.public_ip }
output "ssh_command_new"  { value = "ssh -i ${pathexpand(var.private_key_path)} ubuntu@${aws_instance.from_ami.public_ip}" }
EOF_TF
```

---

### terraform.tfvars

```bash
cat > terraform.tfvars <<'EOF_TF'
aws_region       = "ap-south-1"
instance_type    = "t3.micro"
private_key_path = "~/.ssh/terraform-020-demo"
EOF_TF
```

Update `aws_region` to match your configured region (`aws configure get region`).

---

## 4. Phase 1 — Init, Format, Validate, Targeted Apply

### Initialize

```bash
terraform init
```

Expected output:

```text
- Installing hashicorp/aws v6.x.x...
- Installing hashicorp/tls v4.x.x...
- Installing hashicorp/local v2.x.x...

Terraform has been successfully initialized!
```

### Format and Validate

```bash
terraform fmt
terraform validate
```

Expected:

```text
Success! The configuration is valid.
```

### Targeted Apply — Base Instance Only

At this point `ami.tf` exists in the folder, but you do NOT apply it yet. Use `-target` to create only the base infrastructure:

```bash
terraform apply \
  -target=tls_private_key.demo \
  -target=local_sensitive_file.private_key \
  -target=aws_key_pair.demo \
  -target=aws_security_group.ssh \
  -target=aws_instance.base
```

Type `yes` when prompted.

Expected output:

```text
tls_private_key.demo: Creating...
tls_private_key.demo: Creation complete after 0s
local_sensitive_file.private_key: Creating...
local_sensitive_file.private_key: Creation complete after 0s
aws_key_pair.demo: Creating...
aws_security_group.ssh: Creating...
aws_key_pair.demo: Creation complete after 1s
aws_security_group.ssh: Creation complete after 2s
aws_instance.base: Creating...
aws_instance.base: Creation complete after 14s

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

base_instance_id = "i-07225665a4cd1ed8b"
base_instance_ip = "13.207.57.13"
ssh_command_base = "ssh -i /home/USER/.ssh/terraform-020-demo ubuntu@13.207.57.13"
```

Note: `custom_ami_id`, `new_instance_ip`, and `ssh_command_new` are not shown yet — those resources do not exist until Phase 2.

**Why `-target`?**

The `-target` flag tells Terraform to plan and apply only the listed resources and their dependencies. Without it, Terraform would try to create the AMI immediately — before you have installed anything on the base instance.

---

## 5. SSH Into Base Instance — Install nginx and Write Custom File

Wait ~20 seconds for the instance to finish booting, then SSH in:

```bash
ssh -i ~/.ssh/terraform-020-demo ubuntu@$(terraform output -raw base_instance_ip)
```

When prompted about the host fingerprint, type `yes`.

Inside the instance, run:

```bash
sudo apt-get update && sudo apt-get install -y nginx
echo "Custom build by saravanans - $(date)" | sudo tee /var/www/html/custom.html
sudo systemctl status nginx
exit
```

Expected output of `systemctl status nginx`:

```text
● nginx.service - A high performance web server and a reverse proxy server
     Loaded: loaded (/lib/systemd/system/nginx.service; enabled; vendor preset: enabled)
     Active: active (running) since ...
```

Expected content of `/var/www/html/custom.html` (example from live test):

```text
Custom build by saravanans - Thu May 21 05:57:48 UTC 2026
```

This file is what you are baking into the AMI. The new instance launched from it will have this exact content.

---

## 6. Phase 2 — Full Apply (AMI Creation + New Instance)

Back on your GCE VM, run a full apply with no `-target` flags:

```bash
terraform apply
```

Type `yes` when prompted.

Terraform will now create the two remaining resources from `ami.tf`:

```text
aws_ami_from_instance.custom: Creating...
aws_ami_from_instance.custom: Still creating... [30s elapsed]
aws_ami_from_instance.custom: Still creating... [1m0s elapsed]
aws_ami_from_instance.custom: Still creating... [1m30s elapsed]
aws_ami_from_instance.custom: Still creating... [2m0s elapsed]
aws_ami_from_instance.custom: Still creating... [2m30s elapsed]
aws_ami_from_instance.custom: Still creating... [3m0s elapsed]
aws_ami_from_instance.custom: Creation complete after 3m6s [id=ami-0e1ee1ef58f2e3444]

aws_instance.from_ami: Creating...
aws_instance.from_ami: Creation complete after 13s [id=i-07003f9d8ef591767]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

base_instance_id = "i-07225665a4cd1ed8b"
base_instance_ip = "13.207.57.13"
custom_ami_id    = "ami-0e1ee1ef58f2e3444"
new_instance_ip  = "3.6.91.95"
ssh_command_base = "ssh -i /home/USER/.ssh/terraform-020-demo ubuntu@13.207.57.13"
ssh_command_new  = "ssh -i /home/USER/.ssh/terraform-020-demo ubuntu@3.6.91.95"
```

AMI creation takes **3-4 minutes** — this is normal. AWS is stopping the instance briefly, creating EBS snapshots of all volumes, and registering the AMI.

---

> **Warning — `snapshot_without_reboot = false` stops the base instance temporarily**
>
> When `snapshot_without_reboot = false` (the correct setting), AWS **stops** the base EC2 instance before taking the snapshot. This ensures all data in the OS page cache is flushed to EBS before the snapshot is taken. The base instance is restarted automatically after the snapshot completes.
>
> During this ~3-minute window, your base instance (`terraform-020-base`) will be in a **stopped** state. This is expected and correct. Do not manually start it — AWS will restart it.
>
> See Section 9 for what happens if you use `snapshot_without_reboot = true` instead.

---

## 7. Verify the New Instance

Wait ~20 seconds for the new instance to boot, then SSH in using the key from Phase 1 (both instances share the same key pair):

```bash
ssh -i ~/.ssh/terraform-020-demo ubuntu@$(terraform output -raw new_instance_ip)
```

Inside the new instance, verify everything was inherited from the base:

```bash
nginx -v
```

Expected:

```text
nginx version: nginx/1.18.0 (Ubuntu)
```

```bash
systemctl is-active nginx
```

Expected:

```text
active
```

```bash
cat /var/www/html/custom.html
```

Expected:

```text
Custom build by saravanans - Thu May 21 05:57:48 UTC 2026
```

The timestamp shows the **original install date from the base instance** — not the launch date of this new instance. That is correct and expected. The file was baked into the AMI when the snapshot was taken.

```bash
exit
```

---

## 8. Outputs Reference

```bash
terraform output                          # show all outputs
terraform output -raw base_instance_ip   # just the base IP
terraform output -raw new_instance_ip    # just the new instance IP
terraform output -raw custom_ami_id      # the AMI ID
terraform output -raw ssh_command_base   # SSH command for base instance
terraform output -raw ssh_command_new    # SSH command for new instance
```

---

## 9. Common Pitfall — `snapshot_without_reboot = true`

**Do not use `snapshot_without_reboot = true` in production.**

During the live test, an initial attempt with `snapshot_without_reboot = true` resulted in an **empty `/var/www/html/custom.html`** on the new instance, even though the file was visible on the base instance.

Why this happens:

```text
You write a file on EC2
  → Linux writes it to page cache (RAM)
  → page cache is eventually flushed to EBS (dirty pages → disk)

snapshot_without_reboot = true
  → AWS takes an EBS snapshot WITHOUT stopping the instance
  → The snapshot captures EBS state at that exact moment
  → If the file is still in page cache and not yet on EBS → it is MISSING from the snapshot
  → The new instance launched from that AMI has an empty or missing file
```

The correct setting is `snapshot_without_reboot = false`:

```text
snapshot_without_reboot = false  (default, correct)
  → AWS stops the instance cleanly
  → OS flushes all page cache to EBS
  → Clean, consistent EBS snapshot is taken
  → AMI contains all files exactly as they were
  → Instance is restarted after snapshot
```

| Setting | Instance stopped? | Data consistency | Use for |
|---|---|---|---|
| `snapshot_without_reboot = false` | Yes (briefly) | Guaranteed — all writes flushed | Production AMIs |
| `snapshot_without_reboot = true` | No | Not guaranteed — dirty page cache risk | Non-critical, stateless, read-only workloads |

---

## 10. Destroy

After the demo, destroy all resources:

```bash
terraform destroy
```

Type `yes`.

Expected:

```text
aws_instance.from_ami: Destroying...
aws_instance.from_ami: Destruction complete after 30s
aws_ami_from_instance.custom: Destroying...
aws_ami_from_instance.custom: Destruction complete after 1s
aws_instance.base: Destroying...
aws_instance.base: Destruction complete after 30s
aws_security_group.ssh: Destroying...
aws_key_pair.demo: Destroying...
aws_security_group.ssh: Destruction complete after 1s
aws_key_pair.demo: Destruction complete after 0s
local_sensitive_file.private_key: Destroying...
local_sensitive_file.private_key: Destruction complete after 0s
tls_private_key.demo: Destroying...
tls_private_key.demo: Destruction complete after 0s

Destroy complete! Resources: 7 destroyed.
```

**What `terraform destroy` does to the AMI:**

- `aws_ami_from_instance` is destroyed → Terraform calls `aws ec2 deregister-image` (the AMI is deregistered)
- The underlying **EBS snapshots** that were created as part of the AMI are also deleted by Terraform automatically
- You do not need to manually delete snapshots from the AWS console

Verify the private key is removed from disk:

```bash
ls ~/.ssh/terraform-020-demo
# ls: cannot access '...': No such file or directory
```

Clean up the `.terraform` directory:

```bash
rm -rf .terraform
```

---

## 11. Full Copy-Paste Setup Script

If you want to create all files in one go:

```bash
mkdir -p ~/terraform-aws-ec2-020-demo
cd ~/terraform-aws-ec2-020-demo

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

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "private_key_path" {
  type    = string
  default = "~/.ssh/terraform-020-demo"
}
EOF_TF

cat > main.tf <<'EOF_TF'
resource "tls_private_key" "demo" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.demo.private_key_openssh
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

resource "aws_key_pair" "demo" {
  key_name   = "terraform-020-demo-key"
  public_key = tls_private_key.demo.public_key_openssh
}

resource "aws_security_group" "ssh" {
  name        = "terraform-020-ssh-sg"
  description = "Allow SSH"

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

  tags = { Name = "terraform-020-ssh-sg" }
}

resource "aws_instance" "base" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.demo.key_name
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  associate_public_ip_address = true

  tags = { Name = "terraform-020-base" }
}
EOF_TF

cat > ami.tf <<'EOF_TF'
resource "aws_ami_from_instance" "custom" {
  name                    = "terraform-020-custom-ami"
  source_instance_id      = aws_instance.base.id
  snapshot_without_reboot = false

  tags = { Name = "terraform-020-custom-ami" }
}

resource "aws_instance" "from_ami" {
  ami                         = aws_ami_from_instance.custom.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.demo.key_name
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  associate_public_ip_address = true

  tags = { Name = "terraform-020-from-custom-ami" }
}
EOF_TF

cat > outputs.tf <<'EOF_TF'
output "base_instance_ip" { value = aws_instance.base.public_ip }
output "base_instance_id" { value = aws_instance.base.id }
output "ssh_command_base" { value = "ssh -i ${pathexpand(var.private_key_path)} ubuntu@${aws_instance.base.public_ip}" }
output "custom_ami_id"    { value = aws_ami_from_instance.custom.id }
output "new_instance_ip"  { value = aws_instance.from_ami.public_ip }
output "ssh_command_new"  { value = "ssh -i ${pathexpand(var.private_key_path)} ubuntu@${aws_instance.from_ami.public_ip}" }
EOF_TF

MY_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")

cat > terraform.tfvars <<EOF_TF
aws_region       = "${MY_REGION}"
instance_type    = "t3.micro"
private_key_path = "~/.ssh/terraform-020-demo"
EOF_TF

terraform init
terraform fmt
terraform validate
```

Then Phase 1:

```bash
terraform apply \
  -target=tls_private_key.demo \
  -target=local_sensitive_file.private_key \
  -target=aws_key_pair.demo \
  -target=aws_security_group.ssh \
  -target=aws_instance.base
```

SSH in, install nginx, write custom.html, exit. Then Phase 2:

```bash
terraform apply
```

---

## 12. Final File Structure

```text
terraform-aws-ec2-020-demo/
├── ami.tf                  ← aws_ami_from_instance + new EC2 (Phase 2)
├── main.tf                 ← tls key, local file, key_pair, sg, base EC2 (Phase 1)
├── outputs.tf              ← IPs, IDs, SSH commands
├── providers.tf            ← aws + tls + local providers
├── terraform.tfvars        ← ap-south-1 overrides
├── variables.tf            ← region, instance_type, private_key_path
├── .terraform.lock.hcl
├── terraform.tfstate
└── terraform.tfstate.backup
```

Private key on disk (outside project folder):

```text
~/.ssh/terraform-020-demo    ← created by Terraform on apply, deleted on destroy
```

---

## 13. Concept Summary

| Resource / Concept | What It Does |
|---|---|
| `aws_ami_from_instance` | Creates a custom AMI from a running or stopped EC2 instance |
| `snapshot_without_reboot = false` | Stops the instance before snapshotting — guarantees data consistency |
| `snapshot_without_reboot = true` | Skips the stop — faster, but risks data inconsistency (dirty page cache) |
| Golden image pattern | Bake software/config into an AMI; launch identical instances from it |
| `-target` flag | Apply only specific resources and their dependencies — used to run Phase 1 without creating the AMI prematurely |
| `aws_ami_from_instance` on destroy | Deregisters the AMI and deletes associated EBS snapshots automatically |
| `local_sensitive_file` | Writes the private key to disk; marks content as sensitive so Terraform never prints it |
| `tls_private_key` | Generates an ED25519 SSH key pair inside Terraform — no `ssh-keygen` needed |
| EBS snapshot | The underlying block-level copy of the root volume that backs a custom AMI |
| `data "aws_ami"` | Looks up the latest Ubuntu 22.04 AMI from Canonical — always gets current image |
