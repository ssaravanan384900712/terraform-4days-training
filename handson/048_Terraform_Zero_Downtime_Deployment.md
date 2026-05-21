# 048 — Zero-Downtime Deployment with create_before_destroy

**By:** Saravanan Sundaramoorthy
**Environment:** Local (no AWS credentials needed)
**Time:** ~10 minutes

## Topic

Terraform's default replacement sequence is **destroy-then-create**: when a resource must be replaced (because an in-place update is not possible), Terraform destroys the old resource first and then creates the new one. That gap — even if brief — is a real outage window.

The `create_before_destroy` lifecycle setting reverses this order to **create-then-destroy**: the new resource is fully provisioned and live before the old one is removed. No gap. No outage.

**The default sequence (dangerous for production):**

```
BEFORE:  [OLD resource — running]
STEP 1:  Terraform destroys OLD    ← outage begins here
STEP 2:  Terraform creates NEW
AFTER:   [NEW resource — running]  ← outage ends here
         Gap = STEP 1 → STEP 2 duration
```

**With create_before_destroy:**

```
BEFORE:  [OLD resource — running]
STEP 1:  Terraform creates NEW     ← no outage, both exist briefly
STEP 2:  Terraform destroys OLD
AFTER:   [NEW resource — running]
         Gap = 0
```

**When it matters most:**

| Resource type | Why zero-downtime matters |
|---|---|
| EC2 instances behind an ALB | New instance registered in target group before old is deregistered |
| TLS/ACM certificates | New cert issued before old one is revoked |
| RDS read replicas | Failover target exists before primary replica is removed |
| Lambda function versions | New version published before alias is switched |
| API tokens / secrets | New credential rotated in before old one is deleted |

This lab uses `random_string` and `local_file` (no AWS credentials needed) to demonstrate the mechanics cleanly and cheaply.

---

## What Terraform Creates

```text
random_string.api_token      → API token string (replacement forced by length change)
local_file.app_config        → /tmp/robochef-app-config.txt (written with token value)
```

---

## File Layout

```text
048-zero-downtime/
├── main.tf
└── variables.tf
```

---

## Step 1 — Create the Working Directory

```bash
mkdir -p ~/terraform-labs/048-zero-downtime
cd ~/terraform-labs/048-zero-downtime
```

---

## Step 2 — variables.tf

```hcl
variable "token_length" {
  description = "Length of the generated API token. Changing this forces replacement."
  type        = number
  default     = 16
}
```

---

## Step 3 — main.tf (with create_before_destroy)

```hcl
terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# ---------------------------------------------------------------------------
# API token — random_string forces replacement whenever any argument changes.
# create_before_destroy = true ensures the NEW token exists before the OLD
# one is removed from state (and from the file it populates).
# ---------------------------------------------------------------------------
resource "random_string" "api_token" {
  length  = var.token_length
  special = false
  upper   = false

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# App config file — depends on the token value.
# When the token is replaced, this file is also replaced.
# create_before_destroy here ensures the file is never absent between writes.
# ---------------------------------------------------------------------------
resource "local_file" "app_config" {
  filename = "/tmp/robochef-app-config.txt"
  content  = <<-EOT
    site=robochef.co
    owner=saravanans
    api_token=${random_string.api_token.result}
    token_length=${var.token_length}
  EOT

  lifecycle {
    create_before_destroy = true
  }
}

output "api_token" {
  description = "Current API token value"
  value       = random_string.api_token.result
}

output "config_file" {
  description = "Path of the written app config"
  value       = local_file.app_config.filename
}
```

---

## Step 4 — First Apply (token_length = 16)

```bash
terraform init
terraform apply -auto-approve
```

Expected output:

```
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:
api_token   = "a7kpnwzqrcbd4fhs"
config_file = "/tmp/robochef-app-config.txt"
```

Read the written file:

```bash
cat /tmp/robochef-app-config.txt
```

```
site=robochef.co
owner=saravanans
api_token=a7kpnwzqrcbd4fhs
token_length=16
```

---

## Step 5 — Trigger Replacement (change token_length to 32)

```bash
terraform apply -var="token_length=32"
```

Watch the plan output carefully before confirming:

```
Terraform will perform the following actions:

  # random_string.api_token must be replaced
+/- resource "random_string" "api_token" {
      ~ id     = "a7kpnwzqrcbd4fhs" -> (known after apply)
      ~ length = 16 -> 32             # forces replacement
      ...
    }

  # local_file.app_config must be replaced
+/- resource "local_file" "app_config" {
      ~ content  = <<-EOT
            site=robochef.co
            owner=saravanans
          - api_token=a7kpnwzqrcbd4fhs
          + api_token=(known after apply)
          - token_length=16
          + token_length=32
        EOT
      ...
    }

Plan: 2 to add, 0 to change, 2 to destroy.
```

**The `+/-` symbol** — this is how Terraform shows a `create_before_destroy` replacement. Compare this to the default `-/+` symbol (destroy-then-create) in the section below.

Type `yes` and apply. New output:

```
Outputs:
api_token   = "mxqnpvaefbtjdlrcwzsguohkynpvcqtf"
config_file = "/tmp/robochef-app-config.txt"
```

---

## Step 6 — Understanding Plan Symbols

Terraform uses two distinct symbols for replacement, and they tell you the order:

| Plan symbol | Meaning | Order |
|---|---|---|
| `-/+` | Default: destroy first, then create | **Outage possible** |
| `+/-` | create_before_destroy: create first, then destroy | **No outage** |

The symbol appears at the far left of the resource line in plan output. If you see `-/+` in plan output for a production resource, that is a warning sign.

---

## Step 7 — Demonstrating the Default (WITHOUT create_before_destroy)

To see what the default behaviour looks like, comment out the lifecycle blocks:

```hcl
# lifecycle {
#   create_before_destroy = true
# }
```

Then change `token_length` again (e.g., back to 16) and run `terraform plan`:

```bash
terraform plan -var="token_length=16"
```

Notice the plan symbol changes:

```
  # random_string.api_token must be replaced
-/+ resource "random_string" "api_token" {
      ...
    }
```

The `-/+` symbol means: **destroy OLD, then create NEW**. Restore the lifecycle blocks before applying:

```hcl
lifecycle {
  create_before_destroy = true
}
```

---

## AWS Pattern — Conceptual Reference

In production, `create_before_destroy` is most commonly applied to EC2 instances:

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]   # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  # When the AMI changes, Terraform must replace this instance.
  # Without create_before_destroy, the old instance is terminated
  # before the new one passes health checks — causing a real outage.
  lifecycle {
    create_before_destroy = true
  }
}
```

When used together with an ALB target group and `aws_autoscaling_group`, this pattern enables fully automated zero-downtime deploys: new instance registers, passes health check, old instance deregisters and terminates.

**Note:** This block is shown for reference — do not apply it in this lab, as it requires AWS credentials and incurs cost.

---

## lifecycle Block — Full Reference

The `lifecycle` block supports four settings that can be combined:

```hcl
resource "aws_instance" "web" {
  # ...

  lifecycle {
    # Create replacement before destroying the existing resource
    create_before_destroy = true

    # Prevent accidental destruction of this resource
    prevent_destroy = true

    # Ignore changes to these attributes after initial creation
    ignore_changes = [
      tags,
      user_data,
    ]

    # Replace the resource when these values change (Terraform 1.2+)
    replace_triggered_by = [
      aws_launch_template.app.latest_version
    ]
  }
}
```

These can be combined — for example, `create_before_destroy = true` and `ignore_changes = [ami]` together give you: only replace if YOU explicitly force it, and when you do, do it with zero downtime.

---

## Destroy

```bash
terraform destroy -auto-approve
rm -rf .terraform
```

Verify the file is gone:

```bash
ls /tmp/robochef-app-config.txt 2>/dev/null || echo "File removed — clean."
```

---

## Summary

| Concept | Detail |
|---|---|
| Default replacement order | `-/+` — destroy OLD, then create NEW (downtime gap) |
| `create_before_destroy` order | `+/-` — create NEW, then destroy OLD (no gap) |
| Plan symbol | `-/+` = dangerous for production; `+/-` = zero-downtime |
| Applies to | Any resource that Terraform must replace (not in-place update) |
| Common use cases | EC2 instances, TLS certs, RDS replicas, API tokens |
| Location | Inside a `lifecycle {}` block within the resource block |

The `create_before_destroy` setting is one of the simplest, highest-value lifecycle settings in Terraform. Add it to any stateful resource in production where a downtime gap would be unacceptable.
