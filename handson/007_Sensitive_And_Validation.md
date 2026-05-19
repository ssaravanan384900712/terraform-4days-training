# 007 — Sensitive Files & Variable Validation

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~10 minutes

---

## Concept

After learning outputs (006), this lab covers two important safety features: **sensitive** (hide secrets from terminal) and **validation** (reject bad input before apply).

```
                    ┌─────────────────────┐
                    │   terraform apply    │
                    └──────────┬──────────┘
                               │
                  ┌────────────┴────────────┐
                  ▼                          ▼
           sensitive flag            validation block
           "hide secrets"            "reject bad input"
                  │                          │
                  ▼                          ▼
           password =                "must be dev,
           <sensitive>                staging, or prod"
```

---

## Prerequisites

Create a fresh project (or reuse an existing one):

```bash
mkdir -p ~/tf_works/007_sensitive
cd ~/tf_works/007_sensitive
```

---

## Part 1 — Sensitive Outputs

### Step 1 — Create a resource with a secret value

```bash
cat > main.tf << 'EOF'
resource "random_string" "db_password" {
  length  = 20
  special = true
}

output "password_visible" {
  value = random_string.db_password.result
}
EOF
```

```bash
terraform init
terraform apply -auto-approve
```

```
Outputs:

password_visible = "aB3$kL9m!Qx2Fp7z#Yw4"
```

> The password is displayed in plain text! Anyone watching your terminal or CI logs can see it.

### Step 2 — Mark the output as sensitive

```bash
cat > main.tf << 'EOF'
resource "random_string" "db_password" {
  length  = 20
  special = true
}

output "password_hidden" {
  value     = random_string.db_password.result
  sensitive = true
}
EOF
```

```bash
terraform apply -auto-approve
```

```
Outputs:

password_hidden = <sensitive>
```

> Now it shows `<sensitive>` instead of the actual value.

### Step 3 — How to retrieve the sensitive value

```bash
# This still hides it
terraform output password_hidden
```

```
<sensitive>
```

```bash
# -raw shows the actual value
terraform output -raw password_hidden
```

```
aB3$kL9m!Qx2Fp7z#Yw4
```

```bash
# -json also shows it
terraform output -json password_hidden
```

```json
"aB3$kL9m!Qx2Fp7z#Yw4"
```

> `-raw` and `-json` bypass the sensitive filter. Useful for scripts, but be careful with logs.

---

## Part 2 — Sensitive in Plan Diffs

### Step 4 — Change the password length

```bash
cat > main.tf << 'EOF'
resource "random_string" "db_password" {
  length  = 24
  special = true
}

output "password_hidden" {
  value     = random_string.db_password.result
  sensitive = true
}
EOF
```

```bash
terraform plan
```

```
  # random_string.db_password must be replaced
-/+ resource "random_string" "db_password" {
      ~ id          = (sensitive value)
      ~ length      = 20 -> 24 # forces replacement
      ~ result      = (sensitive value)
        # (9 unchanged attributes hidden)
    }

Changes to Outputs:
  ~ password_hidden = (sensitive value)
```

> The old and new values are hidden as `(sensitive value)` in the diff. Safe to share plan output.

```bash
terraform apply -auto-approve
```

---

## Part 3 — local_sensitive_file

### Step 5 — Create a sensitive file on disk

```bash
cat >> main.tf << 'EOF'

resource "local_sensitive_file" "secret_config" {
  filename = "/tmp/secret.env"
  content  = "DB_PASSWORD=${random_string.db_password.result}\nAPI_KEY=sk-live-abc123"
}

output "secret_file_path" {
  value     = local_sensitive_file.secret_config.filename
  sensitive = true
}
EOF
```

```bash
terraform init   # need local provider now
terraform apply -auto-approve
```

```
local_sensitive_file.secret_config: Creating...
local_sensitive_file.secret_config: Creation complete after 0s

Outputs:

password_hidden  = <sensitive>
secret_file_path = <sensitive>
```

### Step 6 — Verify the file exists (it's still readable on disk)

```bash
cat /tmp/secret.env
```

```
DB_PASSWORD=xY9#mN2$pQ4!wR7@hJ5*kL8&
API_KEY=sk-live-abc123
```

### What sensitive protects vs what it doesn't

```
HIDDEN:                          STILL VISIBLE:
  terraform output               Actual file on disk
  terraform plan diffs           terraform.tfstate (JSON)
  CI/CD log output               terraform output -json
                                 terraform output -raw
```

> **sensitive = UI protection, NOT encryption.** For real security, use a secrets manager (AWS SSM, Secrets Manager, Vault). State files must be stored remotely with encryption.

---

## Part 4 — Variable Validation

### Step 7 — Add a variable with validation

```bash
cat >> main.tf << 'EOF'

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

resource "local_file" "env_marker" {
  filename = "/tmp/env-${var.environment}.txt"
  content  = "Environment: ${var.environment}"
}
EOF
```

```bash
terraform init
```

### Step 8 — Test with an INVALID value

```bash
terraform plan -var='environment=banana'
```

```
╷
│ Error: Invalid value for variable
│
│   on main.tf line XX:
│   XX: variable "environment" {
│
│ Environment must be dev, staging, or prod.
╵
```

> Caught BEFORE plan even runs. No API calls, no resources touched.

### Step 9 — Test with a VALID value

```bash
terraform plan -var='environment=prod'
```

```
  # local_file.env_marker will be created
  + resource "local_file" "env_marker" {
      + content  = "Environment: prod"
      + filename = "/tmp/env-prod.txt"
      ...
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

```bash
terraform apply -auto-approve -var='environment=prod'
cat /tmp/env-prod.txt
```

```
Environment: prod
```

---

## Part 5 — More Validation Patterns

### Step 10 — Add variables with different validation rules

```bash
cat >> main.tf << 'EOF'

variable "app_name" {
  description = "Application name (lowercase letters and hyphens only)"
  type        = string
  default     = "my-app"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.app_name))
    error_message = "App name must start with a letter, lowercase alphanumeric and hyphens only."
  }
}

variable "port" {
  description = "Application port"
  type        = number
  default     = 8080

  validation {
    condition     = var.port >= 1024 && var.port <= 65535
    error_message = "Port must be between 1024 and 65535."
  }
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = { team = "platform" }

  validation {
    condition     = length(var.tags) > 0
    error_message = "At least one tag is required."
  }
}
EOF
```

### Test each validation:

```bash
# Bad app name (starts with number)
terraform plan -var='app_name=123bad'
```

```
│ App name must start with a letter, lowercase alphanumeric and hyphens only.
```

```bash
# Bad port (too low)
terraform plan -var='port=80'
```

```
│ Port must be between 1024 and 65535.
```

```bash
# Empty tags
terraform plan -var='tags={}'
```

```
│ At least one tag is required.
```

```bash
# All valid
terraform plan -var='app_name=web-api' -var='port=3000'
```

```
No changes. (or plan showing new resources)
```

> **Validation runs at plan time** — fast feedback, no wasted API calls.

---

## Part 6 — Clean Up

```bash
terraform destroy -auto-approve
cd ~
rm -rf ~/tf_works/007_sensitive
```

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| `sensitive = true` on output | Hides value in `terraform output` and plan diffs |
| `terraform output -raw` | Retrieves sensitive value (for scripts) |
| `local_sensitive_file` | Creates file with content hidden in plans |
| Sensitive limits | NOT encryption — state file still has plain text |
| `validation` block | Rejects bad input before plan runs |
| `contains()` | Check if value is in a list |
| `can(regex())` | Pattern matching for strings |
| Range checks | `var.port >= 1024 && var.port <= 65535` |
| `length() > 0` | Ensure collection is not empty |

> **Next:** Proceed to **008** for resource chaining, keepers, count, and for_each with the random provider.
