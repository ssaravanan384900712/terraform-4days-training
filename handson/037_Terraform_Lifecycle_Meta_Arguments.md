# 037 — Terraform Lifecycle Meta-Arguments

**By:** Saravanan Sundaramoorthy
**Environment:** Local (no cloud credentials needed)
**Time:** ~15 min

---

## Concept

Every Terraform resource goes through a lifecycle: **create → update → destroy**. The `lifecycle` block lets you override that default behaviour — controlling the order of replacement, protecting critical resources from accidental deletion, and tolerating external drift.

```
Default Terraform lifecycle:
  create  → resource is built
  update  → resource is modified in-place (when possible)
  destroy → resource is removed

lifecycle block overrides:
  create_before_destroy  → reverse the order during replacement
  prevent_destroy        → refuse to delete the resource at all
  ignore_changes         → skip specific attributes when detecting drift
  replace_triggered_by   → force replacement when another resource changes
```

Four settings. Each solves a specific production problem. All usable with local/random providers — no AWS needed.

---

## Prerequisites

Create a fresh project directory:

```bash
mkdir -p ~/tf_works/037_lifecycle
cd ~/tf_works/037_lifecycle
```

Write the provider block:

```bash
cat > main.tf << 'EOF'
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
EOF
```

```bash
terraform init
```

```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/local versions matching "~> 2.0"...
- Finding hashicorp/random versions matching "~> 3.0"...
- Installed hashicorp/local v2.5.1
- Installed hashicorp/random v3.6.2

Terraform has been successfully initialized!
```

---

## Part 1 — create_before_destroy: Zero-Downtime Replacement

### Why it matters

When Terraform replaces a resource (destroy + create), the default order is:

```
Default (destroy-first):
  1. Old resource DESTROYED   ← gap where nothing exists
  2. New resource CREATED

create_before_destroy (create-first):
  1. New resource CREATED     ← both exist briefly
  2. Old resource DESTROYED   ← no gap
```

For load-balanced apps, databases, and tokens this gap causes downtime. `create_before_destroy = true` eliminates it.

### Demo

Add a `random_string` resource that represents an API token:

```bash
cat >> main.tf << 'EOF'

# ── Part 1: create_before_destroy ────────────────────────────────────────────

resource "random_string" "token" {
  length  = 16
  special = false

  lifecycle {
    create_before_destroy = true
  }
}

output "token" {
  value     = random_string.token.result
  sensitive = true
}
EOF
```

```bash
terraform apply -auto-approve
```

```
random_string.token: Creating...
random_string.token: Creation complete after 0s [id=xQ3mKpLwRnBvAsDf]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

Now force a replacement by changing `length` from 16 to 32. A `random_string` always recreates when its arguments change:

```bash
# Inline edit — change length to trigger replacement
sed -i 's/length  = 16/length  = 32/' main.tf
terraform plan
```

```
  # random_string.token must be replaced
+/- resource "random_string" "token" {
      ~ id     = "xQ3mKpLwRnBvAsDf" -> (known after apply)
      ~ length = 16 -> 32            # forces replacement
        ...
    }

Plan: 1 to add, 1 to destroy, 0 to change.
```

Notice the plan shows **`+/-`** (add then destroy) instead of **`-/+`** (destroy then add).

```
+/-  means: create new FIRST, destroy old SECOND  ← create_before_destroy
-/+  means: destroy old FIRST, create new SECOND  ← default
```

```bash
terraform apply -auto-approve
```

```
random_string.token: Creating...
random_string.token: Creation complete after 0s [id=ZzYyCcXxWwVvUuTtSsRrQqPpOoNnMmLl]
random_string.token (deposed): Destroying... [id=xQ3mKpLwRnBvAsDf]
random_string.token: Destruction complete after 0s

Apply complete! Resources: 1 added, 0 changed, 1 destroyed.
```

New token is live before the old one disappears. Zero downtime.

### Real-world use cases

```
create_before_destroy = true is essential for:

  EC2 instances behind a load balancer
    → new instance registers first, old deregisters after

  RDS parameter groups
    → new group applied before old is removed

  TLS certificates
    → new cert in ACM before old is deleted

  Random tokens / API keys
    → service gets new key before old is revoked
```

---

## Part 2 — prevent_destroy: Protect Critical Resources

### Why it matters

`terraform destroy` or a misconfigured plan can accidentally delete production databases, S3 buckets, or config files. `prevent_destroy = true` adds a hard stop — Terraform refuses to proceed and tells you exactly why.

### Demo

Add a file that represents a critical config:

```bash
cat >> main.tf << 'EOF'

# ── Part 2: prevent_destroy ───────────────────────────────────────────────────

resource "local_file" "robochef_config" {
  filename = "/tmp/robochef-critical-config.txt"
  content  = "site=robochef.co\nowner=saravanans\nenv=production"

  lifecycle {
    prevent_destroy = true
  }
}

output "config_path" {
  value = local_file.robochef_config.filename
}
EOF
```

```bash
terraform apply -auto-approve
```

```
local_file.robochef_config: Creating...
local_file.robochef_config: Creation complete after 0s

config_path = "/tmp/robochef-critical-config.txt"

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

Now try to destroy:

```bash
terraform destroy -auto-approve
```

```
╷
│ Error: Instance cannot be destroyed
│
│   on main.tf line 35:
│   35: resource "local_file" "robochef_config" {
│
│ Resource local_file.robochef_config has lifecycle.prevent_destroy set,
│ but the plan calls for this resource to be destroyed. To avoid this error
│ and continue, you must remove the prevent_destroy attribute from the
│ configuration.
╵
```

Terraform refuses. The file is safe.

### How to intentionally destroy a protected resource

You must do this in two steps:

```
Step 1: Remove prevent_destroy from config (or set it to false)
Step 2: Run terraform destroy
```

There is no flag to override `prevent_destroy` at apply time — that is by design. It forces deliberate human action.

### What prevent_destroy does NOT protect against

```
prevent_destroy = true protects against:      NOT against:
  terraform destroy                             deleting the file manually (OS)
  a plan that removes the resource block        terraform state rm
  accidental removal of the resource block      --target destroy of another resource
                                                that causes this one to be destroyed
```

> For databases: combine `prevent_destroy = true` with deletion protection at the provider level (e.g., `deletion_protection = true` on RDS) for belt-and-suspenders safety.

---

## Part 3 — ignore_changes: Tolerating External Drift

### Why it matters

Sometimes a resource is modified outside of Terraform after creation:
- EC2 user_data scripts update config files
- Operators manually patch a setting in the console
- A separate automation tool writes to a file

Without `ignore_changes`, Terraform sees the drift and tries to revert it every `plan`. With `ignore_changes`, you tell Terraform: "I know this attribute drifts — leave it alone."

### Demo

First add a variable for the content and create the resource:

```bash
cat >> main.tf << 'EOF'

# ── Part 3: ignore_changes ────────────────────────────────────────────────────

variable "app_content" {
  type    = string
  default = "version=1.0\nsite=robochef.co"
}

resource "local_file" "app_config" {
  filename = "/tmp/robochef-app-config.txt"
  content  = var.app_content

  lifecycle {
    ignore_changes = [content]
  }
}

output "app_config_path" {
  value = local_file.app_config.filename
}
EOF
```

```bash
terraform apply -auto-approve
```

```
local_file.app_config: Creating...
local_file.app_config: Creation complete after 0s

app_config_path = "/tmp/robochef-app-config.txt"

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

Simulate external drift — something outside Terraform changes the file:

```bash
echo "version=2.5\nsite=robochef.co\npatched_by=ops_team" > /tmp/robochef-app-config.txt
```

Now run plan:

```bash
terraform plan
```

```
No changes. Your infrastructure matches the configuration.
```

Even though the file content changed externally, Terraform reports no changes because `content` is in `ignore_changes`. Without `ignore_changes`, you would see:

```
# What the plan would show WITHOUT ignore_changes:
  # local_file.app_config will be updated in-place
  ~ resource "local_file" "app_config" {
      ~ content = "version=1.0\nsite=robochef.co"
               -> "version=2.5\nsite=robochef.co\npatched_by=ops_team"
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

### Ignoring multiple attributes

```hcl
lifecycle {
  ignore_changes = [content, file_permission]
}
```

### ignore_changes = all

The nuclear option — ignore every attribute of the resource:

```hcl
resource "local_file" "fully_managed_externally" {
  filename = "/tmp/external-ownership.txt"
  content  = "initial"

  lifecycle {
    ignore_changes = all
  }
}
```

```
ignore_changes = all behaviour:
  - Terraform creates the resource on first apply
  - After that, Terraform NEVER modifies it regardless of config or drift
  - Use when: the resource is fully owned by another system after creation
  - Warning: Terraform config no longer reflects reality — document this clearly
```

### Common ignore_changes patterns

```
Resource                   ignore_changes candidates
──────────────────────     ─────────────────────────────────────────────────
aws_instance               user_data (post-boot scripts modify it)
aws_autoscaling_group      desired_capacity (autoscaler manages it)
aws_ecs_service            desired_count (autoscaler manages it)
aws_db_instance            password (secrets rotation manages it)
local_file                 content (external tool writes to it)
kubernetes_deployment      spec[0].replicas (HPA manages it)
```

---

## Part 4 — replace_triggered_by: Cascade Replacement (Terraform 1.2+)

### Why it matters

Sometimes resource B must be replaced whenever resource A changes — even if B's own arguments did not change. `replace_triggered_by` creates that dependency.

```
replace_triggered_by = [resource_A]

Whenever resource_A is replaced or updated → resource_B is also replaced.
```

### Check your Terraform version

```bash
terraform version
```

```
Terraform v1.x.x   ← must be 1.2 or higher for replace_triggered_by
```

### Demo

Add a version token that drives app replacement:

```bash
cat >> main.tf << 'EOF'

# ── Part 4: replace_triggered_by ─────────────────────────────────────────────

resource "random_string" "version" {
  length  = 6
  special = false
  upper   = false

  keepers = {
    deploy_tag = "v1"
  }
}

resource "local_file" "app" {
  filename = "/tmp/robochef-app.txt"
  content  = "robochef app — deployment bundle"

  lifecycle {
    replace_triggered_by = [random_string.version]
  }
}

output "deploy_version" {
  value = random_string.version.result
}

output "app_file" {
  value = local_file.app.filename
}
EOF
```

```bash
terraform apply -auto-approve
```

```
random_string.version: Creating...
random_string.version: Creation complete after 0s [id=k9xmqp]
local_file.app: Creating...
local_file.app: Creation complete after 0s

deploy_version = "k9xmqp"
app_file = "/tmp/robochef-app.txt"

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

Now trigger a new deployment by changing the keeper on `random_string.version`:

```bash
sed -i 's/deploy_tag = "v1"/deploy_tag = "v2"/' main.tf
terraform plan
```

```
  # random_string.version must be replaced
-/+ resource "random_string" "version" {
      ~ id      = "k9xmqp" -> (known after apply)
      ~ keepers = {
          ~ "deploy_tag" = "v1" -> "v2"    # forces replacement
        }
    }

  # local_file.app will be replaced
  # (triggered by a change in random_string.version)
-/+ resource "local_file" "app" {
      ~ id       = "abc123" -> (known after apply)
        content  = "robochef app — deployment bundle"
        filename = "/tmp/robochef-app.txt"
    }

Plan: 2 to add, 0 to change, 2 to destroy.
```

`local_file.app` is replaced even though its `content` and `filename` did not change. The replacement was triggered by the version token changing.

```bash
terraform apply -auto-approve
```

```
random_string.version: Destroying... [id=k9xmqp]
random_string.version: Destruction complete after 0s
random_string.version: Creating...
random_string.version: Creation complete after 0s [id=r7nztw]
local_file.app: Destroying... [id=abc123]
local_file.app: Destruction complete after 0s
local_file.app: Creating...
local_file.app: Creation complete after 0s

deploy_version = "r7nztw"
```

### Real-world use cases for replace_triggered_by

```
Trigger resource                  Caused replacement
──────────────────                ────────────────────────────────────────
aws_launch_template               aws_autoscaling_group
  (new AMI baked in)                (ASG must cycle instances for new AMI)

aws_iam_role                      aws_instance
  (role policy changed)             (re-launch instance with new permissions)

random_string (deploy token)      local_file / aws_ecs_task_definition
  (version bump)                    (force fresh deployment artifact)

tls_cert                          aws_lb_listener
  (cert renewed)                    (listener must re-attach new cert)
```

---

## All Four lifecycle Settings at a Glance

```
┌────────────────────────┬──────────────────────────────────────────────────┐
│ Setting                │ What it does                                     │
├────────────────────────┼──────────────────────────────────────────────────┤
│ create_before_destroy  │ Build new resource before deleting old one       │
│   = true               │ Prevents gaps (zero-downtime replacement)        │
├────────────────────────┼──────────────────────────────────────────────────┤
│ prevent_destroy        │ Terraform refuses to destroy this resource       │
│   = true               │ Must remove flag first — forces human intent     │
├────────────────────────┼──────────────────────────────────────────────────┤
│ ignore_changes         │ Skip listed attributes when comparing state      │
│   = [attr, attr, ...]  │ Accepts "all" to ignore everything               │
│   = all                │ Prevents reverts of externally managed drift     │
├────────────────────────┼──────────────────────────────────────────────────┤
│ replace_triggered_by   │ Replace this resource when listed resource/attr  │
│   = [resource.name]    │ changes. Requires Terraform >= 1.2               │
└────────────────────────┴──────────────────────────────────────────────────┘
```

### lifecycle block syntax

```hcl
resource "some_resource" "example" {
  # ... resource arguments ...

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = true
    ignore_changes        = [attribute_one, attribute_two]
    replace_triggered_by  = [other_resource.name]
  }
}
```

All four can coexist in one `lifecycle` block. Use only what you need.

---

## Plan Symbol Reference

```
  +    will be created
  -    will be destroyed
  ~    will be updated in-place
  -/+  will be destroyed then created  (default replacement)
  +/-  will be created then destroyed  (create_before_destroy replacement)
```

---

## Verify the Files Created

```bash
ls -la /tmp/robochef*.txt
```

```
-rw-r--r-- 1 user user  47 May 21 10:00 /tmp/robochef-app-config.txt
-rw-r--r-- 1 user user  34 May 21 10:00 /tmp/robochef-app.txt
-rw-r--r-- 1 user user  48 May 21 10:00 /tmp/robochef-critical-config.txt
```

```bash
cat /tmp/robochef-critical-config.txt
```

```
site=robochef.co
owner=saravanans
env=production
```

---

## Clean Up

`prevent_destroy` is still set on `local_file.robochef_config`. Remove it first:

```bash
# Remove prevent_destroy so destroy can proceed
sed -i '/prevent_destroy/d' main.tf
terraform destroy -auto-approve
rm -rf ~/tf_works/037_lifecycle
```

```
random_string.token: Destroying...
random_string.version: Destroying...
local_file.app_config: Destroying...
local_file.app: Destroying...
local_file.robochef_config: Destroying...

Destroy complete! Resources: 5 destroyed.
```

---

## Summary

| Setting | Problem it solves | Key behaviour |
|---------|------------------|---------------|
| `create_before_destroy = true` | Downtime during replacement | New resource created first, old destroyed second |
| `prevent_destroy = true` | Accidental deletion of prod resources | Hard error at plan time — must remove flag to delete |
| `ignore_changes = [attr]` | External drift causing unwanted reverts | Listed attributes are skipped in plan comparison |
| `ignore_changes = all` | Resource fully owned externally after creation | No updates ever, only creation and (manual) deletion |
| `replace_triggered_by = [res]` | Cascade replacement across resources | Replacement of dependency forces replacement of this resource |

> **Next:** Proceed to **038** for Terraform loops — for_each on resources, for expressions, and dynamic blocks.
