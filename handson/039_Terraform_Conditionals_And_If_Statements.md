# 039 — Terraform Conditionals: count, for_each & Ternary Expressions

**By:** Saravanan Sundaramoorthy
**Environment:** Local (no cloud credentials needed)
**Time:** ~15 minutes

---

## Concept

Terraform has **no `if`, `else`, or `switch` keywords**. Conditional logic is expressed through three patterns:

```
Pattern 1 — count = 0 or 1         simple if (resource exists or doesn't)
Pattern 2 — ternary operator        condition ? true_val : false_val
Pattern 3 — for_each filtered map   if-else equivalent for complex cases
```

All three patterns are idiomatic Terraform. You will use them constantly.

```
Traditional code:           Terraform equivalent:
  if debug_enabled:           count = var.enable_debug ? 1 : 0
    create_log_file()

  x = env == "prod" ? 32      length = var.environment == "prod" ? 32 : 16
        : 16

  for f in features:          for_each = { for k, v in var.features
    if f.enabled:                          : k => v if v == true }
      create(f)
```

---

## Prerequisites

Create a fresh project:

```bash
mkdir -p ~/tf_works/039_conditionals
cd ~/tf_works/039_conditionals
```

```bash
cat > providers.tf << 'EOF'
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

terraform init
```

```
Initializing provider plugins...
- Installing hashicorp/local v2.x.x...
- Installing hashicorp/random v3.x.x...

Terraform has been successfully initialized!
```

---

## Part 1 — count-Based Conditional (Simple If)

`count = 0` means the resource does **not** exist.
`count = 1` means the resource **does** exist.
`count = condition ? 1 : 0` is the standard Terraform "if" pattern.

### Step 1 — Create the conditional resource

```bash
cat > main.tf << 'EOF'
variable "enable_debug_log" {
  description = "Create a debug log file for robochef.co?"
  type        = bool
  default     = true
}

resource "local_file" "debug_log" {
  count    = var.enable_debug_log ? 1 : 0
  filename = "/tmp/robochef-debug.log"
  content  = "Debug enabled for robochef.co\nOwner: saravanans\n"
}

output "debug_log_path" {
  value = var.enable_debug_log ? local_file.debug_log[0].filename : "debug disabled"
}
EOF
```

### Step 2 — Apply with debug enabled (default = true)

```bash
terraform apply -auto-approve
```

```
local_file.debug_log[0]: Creating...
local_file.debug_log[0]: Creation complete after 0s

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

debug_log_path = "/tmp/robochef-debug.log"
```

```bash
cat /tmp/robochef-debug.log
```

```
Debug enabled for robochef.co
Owner: saravanans
```

> `count = true ? 1 : 0` evaluates to `count = 1` — one resource created.
> The output uses `local_file.debug_log[0].filename` because count resources are always indexed.

### Step 3 — Apply with debug disabled

```bash
terraform apply -auto-approve -var='enable_debug_log=false'
```

```
  # local_file.debug_log[0] will be destroyed

Plan: 0 to add, 0 to change, 1 to destroy.

local_file.debug_log[0]: Destroying...
local_file.debug_log[0]: Destruction complete after 0s

Apply complete! Resources: 0 added, 0 changed, 1 destroyed.

Outputs:

debug_log_path = "debug disabled"
```

> `count = false ? 1 : 0` evaluates to `count = 0` — resource destroyed.
> The output safely returns the string `"debug disabled"` instead of referencing the non-existent `[0]`.

### Why `[0]` is required in the output

```
When count = 1:   local_file.debug_log      → a LIST of 1 item
                  local_file.debug_log[0]   → the single item ← you need this

When count = 0:   local_file.debug_log      → empty list []
                  local_file.debug_log[0]   → ERROR: index out of range

Solution: guard with the same condition:
  value = var.enable_debug_log ? local_file.debug_log[0].filename : "debug disabled"
                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                 Only evaluated when count = 1
```

### Step 4 — Re-enable for next parts

```bash
terraform apply -auto-approve
```

---

## Part 2 — Ternary Operator in Resource Arguments

The ternary operator changes **values inside a resource**, not just whether it exists.

```
condition ? value_if_true : value_if_false
```

### Step 5 — Add ternary expressions in resource blocks

```bash
cat >> main.tf << 'EOF'

variable "environment" {
  description = "Deployment environment: dev, staging, or prod"
  type        = string
  default     = "dev"
}

resource "random_string" "api_key" {
  length  = var.environment == "prod" ? 32 : 16
  special = var.environment == "prod" ? true : false
}

resource "local_file" "app_settings" {
  filename = "/tmp/robochef-settings.txt"
  content  = <<-EOT
    environment=${var.environment}
    log_level=${var.environment == "prod" ? "ERROR" : "DEBUG"}
    replicas=${var.environment == "prod" ? 3 : 1}
    api_key_length=${var.environment == "prod" ? 32 : 16}
    site=robochef.co
    owner=saravanans
  EOT
}

output "api_key_length" {
  value = random_string.api_key.length
}

output "settings_file" {
  value = local_file.app_settings.filename
}
EOF
```

### Step 6 — Apply with dev environment (default)

```bash
terraform apply -auto-approve
```

```
random_string.api_key: Creating...
local_file.app_settings: Creating...

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

api_key_length = 16
settings_file  = "/tmp/robochef-settings.txt"
```

```bash
cat /tmp/robochef-settings.txt
```

```
environment=dev
log_level=DEBUG
replicas=1
api_key_length=16
site=robochef.co
owner=saravanans
```

### Step 7 — Apply with prod environment

```bash
terraform apply -auto-approve -var='environment=prod'
```

```
random_string.api_key: Destroying...
random_string.api_key: Creating...
local_file.app_settings: Modifying...

Apply complete! Resources: 1 added, 1 changed, 1 destroyed.
```

```bash
cat /tmp/robochef-settings.txt
```

```
environment=prod
log_level=ERROR
replicas=3
api_key_length=32
site=robochef.co
owner=saravanans
```

> The ternary in `length` and `special` forced `random_string.api_key` to be recreated (different length = new resource). The `local_file` was modified in place (content changed).

### How ternary evaluation works

```
var.environment == "prod" ? 32 : 16
│                          │     │
│ condition                │     └─ value when FALSE ("dev", "staging")
│                          └─ value when TRUE ("prod")
└─ comparison: returns true or false

"prod" == "prod"  →  true   →  uses 32
"dev"  == "prod"  →  false  →  uses 16
```

### Step 8 — Switch back to dev

```bash
terraform apply -auto-approve -var='environment=dev'
```

---

## Part 3 — for_each with Conditional Map (If-Else Equivalent)

Use a **filtered for expression** to create resources only for items that meet a condition. This is the closest Terraform gets to an if-else loop.

### Step 9 — Feature flag pattern

```bash
cat >> main.tf << 'EOF'

variable "features" {
  description = "Feature flags for robochef.co"
  type        = map(bool)
  default = {
    dark_mode     = true
    notifications = false
    analytics     = true
    beta_features = false
  }
}

resource "local_file" "enabled_features" {
  for_each = { for k, v in var.features : k => v if v == true }
  filename  = "/tmp/robochef-feature-${each.key}.txt"
  content   = "Feature ${each.key} is ENABLED for robochef.co\n"
}

output "enabled_features" {
  value = { for k, v in local_file.enabled_features : k => v.filename }
}

output "disabled_features" {
  value = [for k, v in var.features : k if v == false]
}
EOF
```

### Step 10 — Apply

```bash
terraform apply -auto-approve
```

```
local_file.enabled_features["analytics"]: Creating...
local_file.enabled_features["dark_mode"]: Creating...

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

enabled_features = {
  "analytics" = "/tmp/robochef-feature-analytics.txt"
  "dark_mode"  = "/tmp/robochef-feature-dark_mode.txt"
}

disabled_features = [
  "beta_features",
  "notifications",
]
```

> Only `dark_mode` and `analytics` files were created — the `false` features (`notifications`, `beta_features`) were filtered out. No files created for them.

```bash
ls /tmp/robochef-feature-*.txt
```

```
/tmp/robochef-feature-analytics.txt
/tmp/robochef-feature-dark_mode.txt
```

### How the filtered for expression works

```
{ for k, v in var.features : k => v if v == true }
  │               │            │         │
  │               │            │         └─ FILTER: only include when true
  │               │            └─ output: key => value
  │               └─ iterate over the map
  └─ result is a new map

Input map:
  dark_mode     = true   ← INCLUDED
  notifications = false  ← filtered out
  analytics     = true   ← INCLUDED
  beta_features = false  ← filtered out

Output map:
  dark_mode  = true
  analytics  = true

for_each receives this filtered map → creates 2 resources
```

### Step 11 — Toggle a feature on

```bash
terraform apply -auto-approve -var='features={"dark_mode":true,"notifications":true,"analytics":true,"beta_features":false}'
```

```
  # local_file.enabled_features["notifications"] will be created

Plan: 1 to add, 0 to change, 0 to destroy.

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

> Only the newly-enabled `notifications` resource was created. `dark_mode` and `analytics` were untouched because for_each is key-stable.

### Step 12 — Toggle a feature off

```bash
terraform apply -auto-approve -var='features={"dark_mode":false,"notifications":true,"analytics":true,"beta_features":false}'
```

```
  # local_file.enabled_features["dark_mode"] will be destroyed

Plan: 0 to add, 0 to change, 1 to destroy.

Apply complete! Resources: 0 added, 0 changed, 1 destroyed.
```

> `dark_mode` was removed. The other features were untouched.

---

## Part 4 — Nested Ternary (Multi-Condition)

For more than two outcomes, ternaries can be chained — but use with caution.

### Step 13 — Nested ternary example

```bash
cat >> main.tf << 'EOF'

locals {
  tier = var.environment == "prod" ? "premium" : var.environment == "staging" ? "standard" : "free"

  # The above is equivalent to:
  # if env == "prod"     → "premium"
  # elif env == "staging" → "standard"
  # else                  → "free"
}

resource "local_file" "tier_info" {
  filename = "/tmp/robochef-tier.txt"
  content  = "Environment: ${var.environment}\nTier: ${local.tier}\nSite: robochef.co\n"
}

output "current_tier" {
  value = local.tier
}
EOF
```

```bash
terraform apply -auto-approve
```

```
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

current_tier = "free"
```

```bash
terraform apply -auto-approve -var='environment=staging'
```

```
current_tier = "standard"
```

```bash
terraform apply -auto-approve -var='environment=prod'
```

```
current_tier = "premium"
```

### Warning: Deep nesting is unreadable

```
# BAD: hard to read, hard to maintain
tier = a == "x" ? "1" : a == "y" ? "2" : a == "z" ? "3" : "4"

# GOOD: use a local map lookup instead
locals {
  tier_map = {
    prod    = "premium"
    staging = "standard"
    dev     = "free"
  }
  tier = lookup(local.tier_map, var.environment, "free")
}
```

> Use the map lookup pattern for 3+ conditions. It's readable, extensible, and less error-prone than chained ternaries.

---

## Part 5 — Conditional Output Values

Outputs can also use conditionals to guard against empty collections.

```bash
cat >> main.tf << 'EOF'

output "api_key_value" {
  description = "API key — longer in prod for robochef.co"
  value       = random_string.api_key.result
  sensitive   = true
}

output "resource_summary" {
  value = {
    debug_enabled    = var.enable_debug_log
    environment      = var.environment
    tier             = local.tier
    features_enabled = length({ for k, v in var.features : k => v if v == true })
    features_total   = length(var.features)
  }
}
EOF
```

```bash
terraform apply -auto-approve
```

```
Outputs:

resource_summary = {
  "debug_enabled"    = true
  "environment"      = "prod"
  "features_enabled" = 2
  "features_total"   = 4
  "tier"             = "premium"
}
```

---

## Limitations and Best Practices

```
Terraform conditionals CANNOT:
  ✗  break / continue in loops
  ✗  switch / case statements
  ✗  early return
  ✗  complex boolean short-circuit (no &&, || in count)

Terraform conditionals CAN:
  ✓  count = condition ? 1 : 0      (resource on/off)
  ✓  attr = cond ? val_a : val_b    (attribute switching)
  ✓  for k, v in map : k if cond    (filtered iteration)
  ✓  lookup(map, key, default)      (multi-case lookup)
```

### Decision guide

```
Question: Do I need a resource to exist or not?
  → count = var.enabled ? 1 : 0

Question: Does a resource attribute change based on a condition?
  → attr = var.env == "prod" ? "large" : "small"

Question: Do I need to create resources for some items but not others?
  → for_each = { for k, v in map : k => v if condition }

Question: Do I need 3+ different values based on a key?
  → lookup(local.tier_map, var.environment, "default")
```

---

## Clean Up

```bash
terraform destroy -auto-approve
cd ~
rm -rf ~/tf_works/039_conditionals
rm -rf .terraform
```

---

## Summary

| Pattern | Syntax | Use Case |
|---------|--------|----------|
| count if | `count = var.enabled ? 1 : 0` | Create or skip a resource |
| ternary attribute | `length = var.env == "prod" ? 32 : 16` | Switch a value in a resource |
| filtered for_each | `for k, v in map : k => v if condition` | Create only matching resources |
| nested ternary | `a ? x : b ? y : z` | Multi-case (prefer map lookup) |
| map lookup | `lookup(local.map, var.key, default)` | Clean multi-case alternative |

> **Next:** Proceed to **040** for Terraform's complete built-in function library — 100+ functions with practical examples.
