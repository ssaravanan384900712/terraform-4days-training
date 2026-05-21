# 044 — Debugging Terraform: TF_LOG, Plan Analysis & Tips

**By:** Saravanan Sundaramoorthy
**Environment:** Local
**Time:** ~15 min

---

## Overview

Even well-written Terraform configurations fail in unexpected ways. This lab covers the debugging toolkit built into Terraform: log levels, plan output analysis, state inspection commands, the interactive console, common errors and their fixes, and the difference between `refresh` and `plan -refresh-only`.

---

## Prerequisites

- Terraform 1.6+ installed (`terraform version`)
- A working directory with any `.tf` files (you can use the `local_file` provider for all examples — no AWS credentials needed)
- `jq` installed for JSON filtering (`jq --version`)

---

## 1. TF_LOG — Controlling Terraform Log Verbosity

Terraform's `TF_LOG` environment variable controls how much diagnostic output is written to stderr. Five levels are available, from most verbose to least:

```bash
export TF_LOG=TRACE    # most verbose — every API call, every internal step
export TF_LOG=DEBUG    # detailed internal operations, provider request/response bodies
export TF_LOG=INFO     # informational messages about what Terraform is doing
export TF_LOG=WARN     # warnings only — something may be wrong but execution continues
export TF_LOG=ERROR    # errors only — minimum useful output for troubleshooting
```

### What each level reveals

| Level | What you see |
|-------|-------------|
| TRACE | Every function call, every HTTP request and response body, internal state transitions |
| DEBUG | Provider plugin negotiation, API requests, response codes, retry logic |
| INFO  | Phase transitions (init, plan, apply), resource counts, provider version selection |
| WARN  | Deprecated arguments, unusual but non-fatal conditions |
| ERROR | Failed API calls, authentication errors, state file corruption |

### Saving logs to a file

Writing logs to a file is almost always better than reading them from the terminal. Use `TF_LOG_PATH`:

```bash
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform-debug.log
terraform plan
```

The log file is appended on each run, so clear it between runs if you want a clean trace:

```bash
rm -f terraform-debug.log
terraform plan
```

### Reading a DEBUG log

A DEBUG log can run thousands of lines. Focus on the areas that matter:

```bash
# See every outbound API request
grep "Request" terraform-debug.log | head -20

# See every API response code
grep "Response" terraform-debug.log | head -20

# Find authentication or permission errors
grep -i "403\|401\|forbidden\|unauthorized" terraform-debug.log

# Trace a specific resource type
grep -i "aws_instance" terraform-debug.log | head -30

# Find provider plugin startup
grep "plugin" terraform-debug.log | head -10
```

### Example: reading a TRACE entry

A typical TRACE entry for an HTTP request looks like:

```
2024-01-15T10:23:01.234Z [TRACE] provider.terraform-provider-aws_v5.31.0_x5:
  Request URL: https://ec2.ap-south-1.amazonaws.com/
  Request method: POST
  Request body: Action=DescribeInstances&...
  Response Status: 200 OK
  Response body: <DescribeInstancesResponse>...</DescribeInstancesResponse>
```

This tells you exactly what API call Terraform made, what parameters it sent, and what AWS responded. Useful for diagnosing IAM permission issues — if you see a 403 on a specific action, you know exactly which permission is missing.

### Unsetting log levels

Always unset `TF_LOG` when you are done debugging, otherwise every subsequent command produces noisy output:

```bash
unset TF_LOG
unset TF_LOG_PATH
```

---

## 2. Plan Output Analysis

`terraform plan` output uses a set of symbols to describe what will happen to each resource. Understanding these symbols is critical before running `terraform apply`.

### The five symbols

```
+ create           ← resource does not exist, will be created
~ update in-place  ← resource exists, some attributes will change without recreating it
- destroy          ← resource exists and will be deleted
-/+ destroy then recreate  ← MOST DANGEROUS: resource must be deleted and rebuilt
<= read            ← data source, will be read from API (no infrastructure change)
```

### Destroy-then-recreate (-/+)

This is the symbol that requires the most attention. When you see `-/+`, find the line that says `# forces replacement` — that attribute cannot be changed on a live resource, so Terraform must delete and rebuild it.

```
# aws_instance.web must be replaced
-/+ resource "aws_instance" "web" {
      ~ ami           = "ami-0abcdef1234567890" -> "ami-0newimage9876543210" # forces replacement
        instance_type = "t3.micro"
        ...
    }
```

Common attributes that force replacement:
- `ami` on `aws_instance`
- `name` on many resources that cannot be renamed in-place
- `subnet_id` on `aws_instance` (you cannot move an EC2 to a different subnet)
- `engine` on `aws_db_instance`

### Update in-place (~)

These changes are safe — the resource keeps running while Terraform modifies it:

```
# aws_instance.web will be updated in-place
~ resource "aws_instance" "web" {
      id            = "i-0abcdef1234567890"
    ~ tags          = {
        ~ "Name" = "old-name" -> "new-name"
      }
    }
```

### known after apply

When a value depends on a resource that does not exist yet, Terraform cannot know it during the plan phase:

```
+ resource "aws_instance" "web" {
    + ami           = "ami-0abcdef1234567890"
    + instance_type = "t3.micro"
    + id            = (known after apply)     ← AWS assigns this at creation time
    + public_ip     = (known after apply)     ← depends on whether an EIP is attached
    + private_ip    = (known after apply)
  }
```

If a downstream resource depends on a `(known after apply)` value, its plan will also show `(known after apply)` for the derived attribute. This cascading is normal.

### Reading a complete plan

Before applying, always check:
1. Is there a `-/+` (destroy-then-recreate) you did not expect?
2. Are any `-` (destroy) entries for resources you want to keep?
3. How many resources in total? (`Plan: 3 to add, 1 to change, 0 to destroy.`)

```bash
# Save plan output to a file for review
terraform plan 2>&1 | tee plan-output.txt

# Count operations by type
grep -c "^  + " plan-output.txt
grep -c "^  ~ " plan-output.txt
grep -c "^  -" plan-output.txt
```

---

## 3. State Inspection Commands

The Terraform state file is the source of truth for what resources Terraform manages. These commands let you inspect and manipulate state without editing the JSON file directly.

### Listing resources

```bash
terraform state list
```

Example output:
```
aws_instance.web
aws_s3_bucket.assets
aws_security_group.web_sg
random_id.suffix
```

Filter by resource type:
```bash
terraform state list | grep aws_instance
terraform state list | grep -v data   # exclude data sources
```

### Showing a single resource

```bash
terraform state show aws_instance.web
```

This prints every attribute Terraform knows about that resource in the same format as a `.tf` file:

```
# aws_instance.web:
resource "aws_instance" "web" {
    ami                          = "ami-0abcdef1234567890"
    arn                          = "arn:aws:ec2:ap-south-1:123456789012:instance/i-0abc"
    id                           = "i-0abcdef1234567890"
    instance_type                = "t3.micro"
    private_ip                   = "10.0.1.5"
    public_ip                    = "13.234.56.78"
    ...
}
```

This is useful for finding the exact attribute names and current values before writing `terraform_remote_state` references or data source filters.

### Showing the full state

```bash
terraform show                  # human-readable, all resources
terraform show -json            # raw JSON output
terraform show -json | jq .     # pretty-printed JSON
```

### Moving a resource in state (rename)

Use this when you rename a resource in your `.tf` file and want to avoid destroy-and-recreate:

```bash
# You renamed aws_instance.web to aws_instance.app in your .tf file
terraform state mv aws_instance.web aws_instance.app
```

After the move, run `terraform plan` — it should show no changes.

### Removing a resource from state (dangerous)

This tells Terraform to forget about a resource without destroying it. The real infrastructure remains, but Terraform will no longer manage it:

```bash
terraform state rm aws_instance.web
```

Use cases:
- You want to import a resource into a different workspace or state file
- A resource was deleted manually and you want Terraform to stop complaining about it
- You are restructuring a monolith into modules

After removing, `terraform plan` will show a `+` (create) for that resource because Terraform no longer knows it exists. If you do not want to recreate it, use `terraform import` to re-register it.

### Pulling and pushing state (remote backends)

```bash
terraform state pull > state-backup.json  # download state from remote backend
terraform state push state-backup.json    # upload state to remote backend (very dangerous)
```

Always take a backup before any state manipulation:

```bash
terraform state pull > "state-backup-$(date +%Y%m%d-%H%M%S).json"
```

---

## 4. terraform console — Interactive Expression Testing

`terraform console` opens an interactive REPL where you can evaluate any Terraform expression against your current variables, locals, and state. This is invaluable for debugging complex expressions before committing them to code.

```bash
terraform console
```

### Inspecting variables and locals

```
> var.sites
tolist([
  "robochef.co",
  "robotea.co",
])

> local.config
{
  "owner"  = "saravanans"
  "region" = "ap-south-1"
}
```

### Testing built-in functions

```
> cidrsubnet("10.0.0.0/16", 8, 2)
"10.0.2.0/24"

> cidrsubnet("10.0.0.0/16", 8, 0)
"10.0.0.0/24"

> cidrsubnet("10.0.0.0/16", 8, 5)
"10.0.5.0/24"

> formatdate("YYYY-MM-DD", timestamp())
"2026-05-21"

> replace("robochef-dev", "-", "_")
"robochef_dev"

> length(["a", "b", "c"])
3

> max(5, 12, 3)
12
```

### Testing for expressions

```
> [for s in var.sites : upper(s)]
tolist([
  "ROBOCHEF.CO",
  "ROBOTEA.CO",
])

> [for s in var.sites : upper(s) if length(s) > 10]
tolist([
  "ROBOCHEF.CO",
])

> {for s in var.sites : s => upper(s)}
{
  "robochef.co" = "ROBOCHEF.CO"
  "robotea.co"  = "ROBOTEA.CO"
}
```

### Inspecting state through console

If you have applied resources, you can read their attributes:

```
> aws_instance.web.public_ip
"13.234.56.78"

> aws_instance.web.tags
{
  "Environment" = "dev"
  "Name"        = "robochef-web"
}
```

### Exiting

```
> exit
```

Or press `Ctrl+D`.

---

## 5. Common Errors and Fixes

### "Error: Provider configuration not present"

```
Error: Provider configuration not present

To work with aws_instance.web its original provider configuration at
provider["registry.terraform.io/hashicorp/aws"] is required, but it has been removed.
```

**Cause:** The provider block was removed from your configuration, or you have not run `terraform init` after adding a new provider.

**Fix:**
```bash
terraform init
```

If you moved provider configuration into a module, ensure the module is called and `terraform init` is re-run.

---

### "Error: Cycle"

```
Error: Cycle: aws_security_group.web, aws_instance.web
```

**Cause:** Resource A depends on Resource B, and Resource B depends on Resource A — a circular dependency.

**Fix:** Break the cycle. Common patterns:
- Two security groups that reference each other: create the groups first with no rules, then add ingress/egress rules as separate `aws_security_group_rule` resources.
- Remove unnecessary `depends_on` that creates a false dependency.

```hcl
# Instead of referencing the SG ID in both directions,
# use aws_security_group_rule for cross-references
resource "aws_security_group_rule" "allow_from_app" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.db.id
}
```

---

### "Error: Index out of range"

```
Error: Invalid index

  on main.tf line 15, in resource "aws_instance" "web":
  15:   subnet_id = aws_subnet.public[count.index].id
    |----------------
    | count.index is 0

The given key does not identify an element in this collection value: the
collection has no elements.
```

**Cause:** You are using `count.index` to index into a list, but the list has zero elements, or `count` is zero.

**Fix:** Add a guard with `length()`:

```hcl
count = length(var.subnets) > 0 ? length(var.subnets) : 1
```

Or verify your variable is populated:

```bash
terraform console
> var.subnets
```

---

### "Error: Unsupported argument"

```
Error: Unsupported argument

  on main.tf line 8, in resource "aws_s3_bucket" "assets":
   8:   acl = "private"

An argument named "acl" is not expected here.
```

**Cause:** Provider version mismatch. In newer versions of the AWS provider (4.x+), the `acl` argument moved to a separate `aws_s3_bucket_acl` resource.

**Fix:** Upgrade the provider and update your configuration:

```bash
terraform init -upgrade
```

Then update your code to match the new provider API. Check the provider changelog: `https://registry.terraform.io/providers/hashicorp/aws/latest/docs`.

---

### Lock file conflict

```
Error: Failed to install provider

The provider hashicorp/aws version "~> 4.0" is not compatible with the
lock file's selection of "5.31.0".
```

**Cause:** `.terraform.lock.hcl` contains a version that does not match your constraints, or it was committed from a different machine with a different constraint.

**Fix:**
```bash
rm .terraform.lock.hcl
terraform init
```

Or upgrade to allow the locked version:
```bash
terraform init -upgrade
```

---

### State lock

```
Error: Error acquiring the state lock

Error message: ConditionalCheckFailedException: The conditional request failed
Lock Info:
  ID:        abc12345-dead-beef-1234-abcdef012345
  Path:      s3://my-tfstate/terraform.tfstate
  Operation: OperationTypePlan
  Who:       saravanans@machine
  Created:   2026-05-21 10:23:01 +0000 UTC
```

**Cause:** A previous Terraform run crashed or was killed without releasing the state lock.

**Fix:** If you are certain no other operation is running:

```bash
terraform force-unlock abc12345-dead-beef-1234-abcdef012345
```

Never force-unlock while another operation is genuinely in progress — you risk state corruption.

---

### Backend configuration changed

```
Error: Backend configuration changed

A change in the backend configuration has been detected, which may require
migrating or configuring the newly specified backend.
```

**Fix:**
```bash
terraform init -reconfigure
# or to migrate state from old backend to new:
terraform init -migrate-state
```

---

## 6. terraform refresh vs plan -refresh-only

### terraform refresh (deprecated)

```bash
terraform refresh
```

This command updates the Terraform state file to match the real infrastructure — but it does NOT show you what changed, and it writes changes to state immediately. It is deprecated in Terraform 1.x because it silently modifies state without review.

### terraform plan -refresh-only (recommended)

```bash
terraform plan -refresh-only
```

This does the same refresh but shows you what changed in state before committing anything. You then decide whether to apply:

```bash
terraform apply -refresh-only
```

### When to use -refresh-only

- Someone manually changed infrastructure outside Terraform (console, CLI, other tool)
- You want to sync state without making any infrastructure changes
- After an import, to verify state matches reality

```bash
# Workflow: detect drift, decide whether to accept or revert
terraform plan -refresh-only     # shows what changed outside Terraform
terraform apply -refresh-only    # accept those changes into state
terraform plan                   # now plan any Terraform-managed changes on top
```

### Skipping refresh entirely

In large environments, the refresh phase (reading every resource from the API) can take minutes. Skip it when you know nothing changed outside Terraform:

```bash
terraform plan -refresh=false
terraform apply -refresh=false
```

---

## 7. Quick Reference: Debugging Workflow

When a `terraform apply` fails or produces unexpected output, follow this sequence:

```bash
# Step 1: Enable debug logging for the next run
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform-debug.log

# Step 2: Run the failing command
terraform plan

# Step 3: Search the log for errors
grep -i "error\|fail\|denied\|403\|401" terraform-debug.log | head -30

# Step 4: Inspect current state
terraform state list
terraform state show <failing-resource>

# Step 5: Test expressions interactively
terraform console
# > your expression here

# Step 6: Clean up logging
unset TF_LOG
unset TF_LOG_PATH
```

---

## 8. Hands-On Exercise

Create a working directory and try each debugging command:

```bash
mkdir -p /tmp/tf-debug-lab
cd /tmp/tf-debug-lab
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

variable "sites" {
  type    = list(string)
  default = ["robochef.co", "robotea.co"]
}

variable "environment" {
  type    = string
  default = "dev"
}

locals {
  config = {
    owner  = "saravanans"
    region = "ap-south-1"
  }
  site_count = length(var.sites)
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "local_file" "config" {
  for_each = toset(var.sites)

  filename = "/tmp/robochef-${each.key}-config.txt"
  content  = <<-EOT
    site=${each.key}
    environment=${var.environment}
    owner=${local.config.owner}
    suffix=${random_id.suffix.hex}
  EOT
}

output "config_files" {
  value = [for f in local_file.config : f.filename]
}

output "site_count" {
  value = local.site_count
}
```

```bash
terraform init
```

Try each command:

```bash
# 1. Enable debug logging
export TF_LOG=INFO
terraform plan
unset TF_LOG

# 2. Save plan and inspect it
terraform plan -out=plan.tfplan
terraform show plan.tfplan
terraform show -json plan.tfplan | jq '.resource_changes[].change.actions'

# 3. Apply
terraform apply -auto-approve

# 4. List and show state
terraform state list
terraform state show 'local_file.config["robochef.co"]'

# 5. Interactive console
terraform console <<'EOF'
var.sites
local.site_count
[for s in var.sites : upper(s)]
cidrsubnet("10.0.0.0/16", 8, 2)
EOF

# 6. Refresh-only plan (nothing changed outside Terraform, so no drift)
terraform plan -refresh-only

# 7. Rename a resource in state
terraform state mv 'local_file.config["robochef.co"]' 'local_file.config["robochef.co"]'
# (same name — this is just a demo of the syntax)

# 8. Clean up
terraform destroy -auto-approve
rm -rf .terraform .terraform.lock.hcl terraform.tfstate* plan.tfplan terraform-debug.log
```

---

## Summary

| Tool | Purpose |
|------|---------|
| `TF_LOG=DEBUG` | Verbose logs for provider API calls and internal operations |
| `TF_LOG_PATH` | Save logs to file for review |
| Plan symbols (`+`, `~`, `-/+`, `-`, `<=`) | Understand what will change and why |
| `# forces replacement` | Attribute that triggers destroy-then-recreate |
| `terraform state list/show` | Inspect currently managed resources |
| `terraform state mv` | Rename resource in state (avoid recreate after rename) |
| `terraform state rm` | Deregister resource from state without destroying it |
| `terraform console` | Test expressions, functions, and state values interactively |
| `terraform plan -refresh-only` | Detect drift without making infrastructure changes |
| `terraform force-unlock` | Release a stuck state lock |
