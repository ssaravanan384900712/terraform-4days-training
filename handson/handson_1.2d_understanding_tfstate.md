# Hands-On 1.2d — Understanding Terraform State (tfstate)

**Directory:** `lab-state/`

---

## Concept

Terraform state is the **brain** of Terraform. Without it, Terraform doesn't know what it created, what exists in the real world, or what needs to change.

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Your Code   │     │  State File  │     │ Real World   │
│  (main.tf)   │     │  (tfstate)   │     │ (Resources)  │
│              │     │              │     │              │
│ "I want 2   │     │ "There are   │     │ Server A: ✅ │
│  servers"    │     │  2 servers"  │     │ Server B: ✅ │
└──────┬───────┘     └──────┬───────┘     └──────┬───────┘
       │                    │                    │
       └────────┬───────────┘                    │
                │    terraform plan               │
                │    compares these ──────────────┘
                ▼
        "No changes needed" (or shows diff)
```

### Why State Matters

| Without State | With State |
|--------------|-----------|
| Terraform doesn't know what it created | Tracks every resource and its attributes |
| Can't detect drift (manual changes) | Compares state vs reality on every plan |
| Can't update — would try to create duplicates | Knows resource IDs, updates in-place |
| Can't destroy — doesn't know what to remove | Destroys exactly what it manages |
| No dependency tracking | Knows creation order and relationships |

### State File Sensitivity

```
⚠️  terraform.tfstate contains SECRETS:
    - Database passwords
    - API keys
    - Private IPs
    - Resource ARNs
    - Everything Terraform knows about your infra

    NEVER commit to git. Store remotely (S3 + DynamoDB).
```

---

## Step-by-Step: Exploring State

### Step 1 — Create a project with multiple resources

```bash
mkdir -p ~/labs/lab-state
cd ~/labs/lab-state
```

Create `main.tf`:

```hcl
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

variable "project" {
  default = "myapp"
}

variable "environments" {
  default = ["dev", "staging", "prod"]
}

# A unique deployment ID
resource "random_id" "deploy" {
  byte_length = 4
}

# Config file per environment
resource "local_file" "config" {
  count    = length(var.environments)
  filename = "${path.module}/output/${var.environments[count.index]}.conf"
  content  = <<-EOF
    [${var.environments[count.index]}]
    project    = ${var.project}
    deploy_id  = ${random_id.deploy.hex}
    created_at = managed-by-terraform
  EOF
}

# A sensitive secrets file
resource "local_sensitive_file" "secret" {
  filename = "${path.module}/output/secrets.env"
  content  = "DB_PASSWORD=super-secret-${random_id.deploy.hex}"
}

output "deploy_id" {
  value = random_id.deploy.hex
}

output "config_files" {
  value = local_file.config[*].filename
}

output "secret_file" {
  value     = local_sensitive_file.secret.filename
  sensitive = true
}
```

### Step 2 — Initialize and apply

```bash
terraform init
terraform apply -auto-approve
```

Expected output (end):

```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

config_files = [
  "./output/dev.conf",
  "./output/staging.conf",
  "./output/prod.conf",
]
deploy_id = "a1b2c3d4"
secret_file = <sensitive>
```

---

## Exploring the State File

### Step 3 — View state file basics

```bash
ls -la terraform.tfstate
```

```
-rw-r--r-- 1 user user 4523 ... terraform.tfstate
```

> The state file is plain JSON. Let's explore its structure.

### Step 4 — State file top-level structure

```bash
python3 -c "
import json
with open('terraform.tfstate') as f:
    state = json.load(f)
print(f'Version:    {state[\"version\"]}')
print(f'TF Version: {state[\"terraform_version\"]}')
print(f'Serial:     {state[\"serial\"]}')
print(f'Lineage:    {state[\"lineage\"][:20]}...')
print(f'Resources:  {len(state[\"resources\"])}')
print(f'Outputs:    {list(state[\"outputs\"].keys())}')
"
```

Expected output:

```
Version:    4
TF Version: 1.9.0
Serial:     3
Lineage:    abc123de-f456-7890...
Resources:  3
Outputs:    ['config_files', 'deploy_id', 'secret_file']
```

### Key fields explained

| Field | Purpose |
|-------|---------|
| `version` | State file format version (always 4 currently) |
| `terraform_version` | Terraform version that last wrote this state |
| `serial` | Increments on every state change (used for locking) |
| `lineage` | Unique ID for this state — prevents accidental overwrites |
| `resources` | Array of all managed resources with full attributes |
| `outputs` | Values from output blocks |

---

## State CLI Commands

### Step 5 — terraform state list

Lists all resources Terraform is tracking:

```bash
terraform state list
```

```
local_file.config[0]
local_file.config[1]
local_file.config[2]
local_sensitive_file.secret
random_id.deploy
```

> Notice `count` creates indexed entries: `[0]`, `[1]`, `[2]`.

### Step 6 — terraform state show

Show full details of one resource:

```bash
terraform state show random_id.deploy
```

```
# random_id.deploy:
resource "random_id" "deploy" {
    b64_std = "obc0dA=="
    b64_url = "obc0dA"
    byte_length = 4
    dec  = "2814632052"
    hex  = "a1b7b474"
    id   = "obc0dA"
}
```

```bash
terraform state show 'local_file.config[0]'
```

```
# local_file.config[0]:
resource "local_file" "config" {
    content              = <<-EOT
        [dev]
        project    = myapp
        deploy_id  = a1b7b474
        created_at = managed-by-terraform
    EOT
    content_md5          = "abc123..."
    directory_permission = "0777"
    file_permission      = "0777"
    filename             = "./output/dev.conf"
    id                   = "abc123..."
}
```

> **Tip:** Quote resource addresses with `[]` in them to prevent shell expansion.

### Step 7 — terraform output

```bash
# All outputs
terraform output

# Specific output
terraform output deploy_id

# Raw value (no quotes)
terraform output -raw deploy_id

# JSON format
terraform output -json

# Sensitive output — requires -json flag
terraform output -json secret_file
```

---

## State Operations

### Step 8 — terraform state mv (rename a resource)

Rename without destroying and recreating:

```bash
# See current name
terraform state list | grep random

# Rename it
terraform state mv random_id.deploy random_id.deployment

# Verify
terraform state list | grep random
```

```
random_id.deployment
```

> **Important:** You must also rename it in your `.tf` file to match, or the next plan will show create + destroy.

Update `main.tf` — change `random_id.deploy` to `random_id.deployment` everywhere, then:

```bash
terraform plan
```

```
No changes. Your infrastructure matches the configuration.
```

### Step 9 — terraform state rm (unmanage a resource)

Remove a resource from state WITHOUT destroying it:

```bash
# Remove from Terraform's control
terraform state rm 'local_file.config[2]'
```

```
Removed local_file.config[2]
Successfully removed 1 resource instance(s).
```

```bash
# The file still exists!
cat output/prod.conf
```

```
[prod]
project    = myapp
deploy_id  = a1b7b474
...
```

```bash
# But Terraform no longer knows about it
terraform state list
```

```
local_file.config[0]
local_file.config[1]
local_sensitive_file.secret
random_id.deployment
```

> **Use case:** You want to stop managing a resource with Terraform but keep it running. Common during migrations.

### Step 10 — terraform state pull / push

```bash
# Download state to a local file
terraform state pull > state-backup.json

# View it
python3 -m json.tool state-backup.json | head -5

# Push is used with remote backends:
# terraform state push state-backup.json
```

> **state pull** is how you back up state. Always do this before risky operations.

---

## Understanding State Drift

### Step 11 — Simulate drift (manual change)

```bash
# Manually edit a Terraform-managed file
echo "MANUALLY CHANGED" > output/dev.conf
```

### Step 12 — Detect drift with plan

```bash
terraform plan
```

Expected output:

```
local_file.config[0]: Refreshing state... [id=abc123...]

  # local_file.config[0] will be updated in-place
  ~ resource "local_file" "config" {
      ~ content              = "MANUALLY CHANGED\n" -> <<-EOT
            [dev]
            project    = myapp
            ...
        EOT
      ~ content_md5          = "..." -> (known after apply)
        # (3 unchanged attributes hidden)
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

> **Drift detection:** Terraform compares state → real world on every plan. It detected someone changed the file outside Terraform and wants to fix it.

### Step 13 — Fix the drift

```bash
terraform apply -auto-approve
```

The file is restored to what your code declares.

---

## State Backup and Serial Numbers

### Step 14 — Examine the backup file

```bash
ls terraform.tfstate*
```

```
terraform.tfstate
terraform.tfstate.backup
```

```bash
python3 -c "
import json
for f in ['terraform.tfstate', 'terraform.tfstate.backup']:
    with open(f) as fh:
        s = json.load(fh)
    print(f'{f}: serial={s[\"serial\"]}, resources={len(s[\"resources\"])}')
"
```

```
terraform.tfstate: serial=7, resources=4
terraform.tfstate.backup: serial=6, resources=4
```

> The backup is the PREVIOUS state. If something goes wrong, you can restore from it.

---

## The Refresh Cycle

### Step 15 — terraform refresh (deprecated but important to understand)

```bash
# Old way (deprecated):
terraform refresh

# New way — built into plan:
terraform plan -refresh-only
```

```
No changes. Your infrastructure matches the configuration.
```

> Every `terraform plan` and `terraform apply` automatically refreshes state by reading real resources. The `-refresh-only` flag ONLY refreshes state without planning changes.

---

## Summary: State Lifecycle

```
Write Code → init → plan (reads state + real world) → apply (updates state)
                                                          │
                              ┌────────────────────────────┘
                              ▼
                        terraform.tfstate
                              │
                    ┌─────────┼─────────┐
                    ▼         ▼         ▼
               state list  state show  state mv/rm
                    │
                    ▼
              Detect drift ← someone changed resource manually
                    │
                    ▼
              plan shows fix → apply restores declared state
```

### State Commands Cheat Sheet

| Command | Purpose |
|---------|---------|
| `terraform state list` | List all managed resources |
| `terraform state show ADDR` | Show one resource's details |
| `terraform state mv OLD NEW` | Rename without destroy/create |
| `terraform state rm ADDR` | Stop managing (don't destroy) |
| `terraform state pull` | Download state as JSON |
| `terraform state push` | Upload state (use with care!) |
| `terraform plan -refresh-only` | Check for drift only |
| `terraform apply -refresh-only` | Update state to match reality |

---

## Clean Up

```bash
terraform destroy -auto-approve
cd ~
rm -rf ~/labs/lab-state
```

> **Next:** Now you understand state fully. In Day 2, you'll learn about **remote state** (S3 + DynamoDB) for team collaboration. Proceed to **Hands-On 1.3** to deploy your first AWS EC2 instance!
