# 004 — Outputs, Sensitive Files & Validation

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~10 minutes

---

## Concept

After creating resources, you need to **see results** (outputs), **protect secrets** (sensitive), and **validate inputs** (validation). This lab covers all three.

```
                    ┌─────────────────────┐
                    │   terraform apply    │
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
        output block     sensitive flag    validation block
        "show result"    "hide secrets"    "reject bad input"
              │                │                │
              ▼                ▼                ▼
        file_paths =     password =        "must be dev,
        { greeting=...}  <sensitive>        staging, or prod"
```

---

## Prerequisites

Continue in the same directory from 002b (resources already created):

```bash
cd ~/tf_works/002_variables
```

---

## Part 1 — Outputs

### Step 1 — Create outputs.tf

```bash
cat > outputs.tf << 'EOF'
output "file_paths" {
  description = "Paths of all created files"
  value       = { for k, v in local_file.configs : k => v.filename }
}

output "file_count" {
  description = "Number of files created"
  value       = length(local_file.configs)
}

output "team_list" {
  description = "Team members"
  value       = var.team_members
}
EOF
```

### What does this mean?

```
output "file_paths" {
  │       │
  │       └── Name: how you query it (terraform output file_paths)
  │
  description = "..."    ← Help text
  value = { for k, v ... }  ← Computed value (a for expression building a map)
}
```

### Step 2 — Apply to see outputs

```bash
terraform apply -auto-approve
```

```
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

file_count = 3
file_paths = {
  "farewell" = "/tmp/farewell.txt"
  "greeting" = "/tmp/greeting.txt"
  "reminder" = "/tmp/reminder.txt"
}
team_list = [
  "Alice",
  "Bob",
  "Charlie",
]
```

### Step 3 — Query outputs

```bash
# All outputs
terraform output
```

```bash
# Specific value
terraform output file_count
```

```
3
```

```bash
# JSON format (useful for scripts)
terraform output -json file_paths
```

```json
{"farewell":"/tmp/farewell.txt","greeting":"/tmp/greeting.txt","reminder":"/tmp/reminder.txt"}
```

> **Outputs are useful for:** displaying results, passing values to other modules, feeding into scripts or CI/CD pipelines.

---

## Part 2 — Sensitive Files

### Step 4 — Add a sensitive file resource

```bash
cat >> main.tf << 'EOF'

resource "local_sensitive_file" "secret" {
  filename = "/tmp/secret.env"
  content  = "DB_PASSWORD=super_s3cret_p@ssw0rd"
}
EOF
```

Add a sensitive output:

```bash
cat >> outputs.tf << 'EOF'

output "secret_path" {
  value     = local_sensitive_file.secret.filename
  sensitive = true
}
EOF
```

### Step 5 — Apply and observe

```bash
terraform apply -auto-approve
```

```
local_sensitive_file.secret: Creating...
local_sensitive_file.secret: Creation complete after 0s [id=...]

Outputs:

file_count  = 3
file_paths  = { ... }
secret_path = <sensitive>
team_list   = [ ... ]
```

> `secret_path = <sensitive>` — Terraform hides it in terminal output.

### Step 6 — The file still exists on disk

```bash
cat /tmp/secret.env
```

```
DB_PASSWORD=super_s3cret_p@ssw0rd
```

### What sensitive does and does NOT do

| | Visible? |
|--|---------|
| `terraform output` | ❌ Shows `<sensitive>` |
| `terraform plan` diff | ❌ Hidden in diffs |
| Actual file on disk | ✅ Readable |
| `terraform.tfstate` | ✅ Stored in plain text |
| `terraform output -json` | ✅ Shows real value |

> **Key takeaway:** `sensitive` is a UI protection, not security. State file always has the real value. That's why you never commit state to git.

---

## Part 3 — Variable Validation

### Step 7 — Add a validated variable

```bash
cat >> variables.tf << 'EOF'

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}
EOF
```

### Step 8 — Test with an INVALID value

```bash
terraform plan -var='environment=banana'
```

```
╷
│ Error: Invalid value for variable
│
│   on variables.tf line XX:
│   XX: variable "environment" {
│
│ Environment must be dev, staging, or prod.
╵
```

> Validation catches bad input BEFORE Terraform touches any resources.

### Step 9 — Test with a VALID value

```bash
terraform plan -var='environment=prod'
```

```
No changes. Your infrastructure matches the configuration.
```

### Common validation patterns

```hcl
# Must be lowercase letters only
validation {
  condition     = can(regex("^[a-z]+$", var.name))
  error_message = "Name must be lowercase letters only."
}

# Must be in a range
validation {
  condition     = var.port >= 1024 && var.port <= 65535
  error_message = "Port must be between 1024 and 65535."
}

# Must not be empty
validation {
  condition     = length(var.name) > 0
  error_message = "Name cannot be empty."
}
```

---

## Part 4 — State Inspection

### Step 10 — List everything Terraform manages

```bash
terraform state list
```

```
local_file.configs["farewell"]
local_file.configs["greeting"]
local_file.configs["reminder"]
local_sensitive_file.secret
```

### Step 11 — Show details of one resource

```bash
terraform state show 'local_file.configs["greeting"]'
```

```
# local_file.configs["greeting"]:
resource "local_file" "configs" {
    content              = "  File: greeting\n  Message: Hello Folks of MassMutual\n  ..."
    content_md5          = "abc123..."
    directory_permission = "0777"
    file_permission      = "0777"
    filename             = "/tmp/greeting.txt"
    id                   = "abc123..."
}
```

> State shows every attribute Terraform tracks, including computed values like `content_md5`.

---

## Part 5 — Clean Up

```bash
terraform destroy -auto-approve
```

```
Destroy complete! Resources: 4 destroyed.
```

```bash
# Verify
ls /tmp/greeting.txt /tmp/farewell.txt /tmp/reminder.txt /tmp/secret.env 2>&1
```

```
ls: cannot access '/tmp/greeting.txt': No such file or directory
ls: cannot access '/tmp/farewell.txt': No such file or directory
ls: cannot access '/tmp/reminder.txt': No such file or directory
ls: cannot access '/tmp/secret.env': No such file or directory
```

---

## Full 002 Series Summary

| Lab | Concepts |
|-----|----------|
| **002a** | Variables, tfvars, -var, TF_VAR_, precedence |
| **002b** | Types (string/number/bool/list/map), for_each, each.key/value |
| **002c** | Outputs, sensitive, validation, state inspection |

> **Next:** Proceed to **005** to learn the Random provider, resource chaining, and count.
