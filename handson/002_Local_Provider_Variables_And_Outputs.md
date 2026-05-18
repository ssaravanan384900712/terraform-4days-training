# 002 — Local Provider: Variables, Outputs & Multiple Resources

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~25 minutes

---

## Concept

In 001 we hardcoded everything. Real Terraform code uses **variables** (inputs), **outputs** (results), and manages **multiple resources**. This lab teaches all three — still using the local provider, no cloud needed.

```
┌────────────────────────────────────────────────────────┐
│                                                        │
│  variables.tf  ──►  main.tf  ──►  outputs.tf          │
│  (inputs)           (logic)       (results)            │
│                                                        │
│  "What do you       "Create       "Here's what        │
│   want?"             these"        was created"        │
│                                                        │
└────────────────────────────────────────────────────────┘
```

---

## Part 1 — Setup

### Step 1 — Create a fresh project

```bash
mkdir -p ~/tf_works/002_variables
cd ~/tf_works/002_variables
```

---

## Part 2 — Your First Variable

### Step 2 — Create main.tf with a hardcoded value

```bash
cat > main.tf << 'EOF'
resource "local_file" "greeting" {
  content  = "Hello Folks of MassMutual"
  filename = "/tmp/greeting.txt"
}
EOF
```

This works, but the content is stuck. What if we want to change the message without editing main.tf?

### Step 3 — Extract the content into a variable

Replace `main.tf`:

```bash
cat > main.tf << 'EOF'
resource "local_file" "greeting" {
  content  = var.message
  filename = "/tmp/greeting.txt"
}
EOF
```

### Step 4 — Create variables.tf

```bash
cat > variables.tf << 'EOF'
variable "message" {
  description = "The greeting message to write"
  type        = string
  default     = "Hello Folks of MassMutual"
}
EOF
```

### What does this mean?

```
variable "message" {
  │         │
  │         └── Name: how you reference it (var.message)
  │
  description = "..."   ← Human-readable help text
  type        = string  ← Must be a string (not number, bool, etc.)
  default     = "..."   ← Used if no value is provided
}
```

### Step 5 — Init and apply

```bash
terraform init
terraform apply -auto-approve
```

```
local_file.greeting: Creating...
local_file.greeting: Creation complete after 0s [id=4f10852c...]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

```bash
cat /tmp/greeting.txt
```

```
Hello Folks of MassMutual
```

> Same result — the `default` value was used since we didn't provide one.

---

## Part 3 — Passing Variable Values

### Step 6 — Override via CLI flag

```bash
terraform apply -auto-approve -var='message=Hello from the CLI!'
```

```
local_file.greeting: Refreshing state...

  # local_file.greeting must be replaced
-/+ resource "local_file" "greeting" {
      ~ content = "Hello Folks of MassMutual" -> "Hello from the CLI!"
      ...
    }

local_file.greeting: Destroying... [id=4f10852c...]
local_file.greeting: Destruction complete after 0s
local_file.greeting: Creating...
local_file.greeting: Creation complete after 0s [id=...]

Apply complete! Resources: 1 added, 0 changed, 1 destroyed.
```

```bash
cat /tmp/greeting.txt
```

```
Hello from the CLI!
```

> The `-var` flag overrides the default. Notice `-/+` (replace) — the file was destroyed and recreated because the content changed.

### Step 7 — Override via terraform.tfvars file

```bash
cat > terraform.tfvars << 'EOF'
message = "Hello from terraform.tfvars!"
EOF
```

```bash
terraform apply -auto-approve
```

```bash
cat /tmp/greeting.txt
```

```
Hello from terraform.tfvars!
```

> Terraform automatically loads `terraform.tfvars` if it exists. No flag needed.

### Step 8 — Override via environment variable

```bash
export TF_VAR_message="Hello from environment variable!"
terraform apply -auto-approve
```

```bash
cat /tmp/greeting.txt
```

```
Hello from environment variable!
```

```bash
unset TF_VAR_message
```

> Pattern: `TF_VAR_` + variable name. Useful in CI/CD pipelines.

### Variable Precedence (lowest to highest)

```
1. default in variables.tf     ← lowest priority
2. terraform.tfvars file
3. *.auto.tfvars files
4. -var-file="custom.tfvars"
5. -var='key=value' CLI flag
6. TF_VAR_name environment var  ← highest priority
```

> **Tip:** Remove the tfvars file for now so defaults are used going forward:

```bash
rm terraform.tfvars
```

---

## Part 4 — Variable Types

### Step 9 — Add more variables with different types

Update `variables.tf`:

```bash
cat > variables.tf << 'EOF'
variable "message" {
  description = "The greeting message"
  type        = string
  default     = "Hello Folks of MassMutual"
}

variable "file_count" {
  description = "Number of files to create"
  type        = number
  default     = 3
}

variable "add_timestamp" {
  description = "Whether to add a timestamp line"
  type        = bool
  default     = true
}

variable "team_members" {
  description = "List of team member names"
  type        = list(string)
  default     = ["Alice", "Bob", "Charlie"]
}

variable "file_config" {
  description = "Configuration per file"
  type = map(string)
  default = {
    greeting  = "/tmp/greeting.txt"
    farewell  = "/tmp/farewell.txt"
    reminder  = "/tmp/reminder.txt"
  }
}
EOF
```

### Variable Types Cheat Sheet

```
string    →  "hello"               var.message
number    →  42                    var.file_count
bool      →  true / false         var.add_timestamp
list      →  ["a", "b", "c"]     var.team_members[0]
map       →  { key = "value" }    var.file_config["greeting"]
```

---

## Part 5 — Multiple Resources

### Step 10 — Create multiple files using the map variable

Update `main.tf`:

```bash
cat > main.tf << 'EOF'
resource "local_file" "configs" {
  for_each = var.file_config

  filename = each.value
  content  = <<-EOT
    File: ${each.key}
    Message: ${var.message}
    Team: ${join(", ", var.team_members)}
    Timestamp enabled: ${var.add_timestamp}
  EOT
}
EOF
```

### What does for_each do?

```
for_each = var.file_config
           │
           └── Iterates over the map:
               "greeting" = "/tmp/greeting.txt"
               "farewell" = "/tmp/farewell.txt"
               "reminder" = "/tmp/reminder.txt"

each.key   → "greeting", "farewell", "reminder"
each.value → "/tmp/greeting.txt", "/tmp/farewell.txt", "/tmp/reminder.txt"
```

### Step 11 — Apply

```bash
terraform apply -auto-approve
```

```
local_file.configs["farewell"]: Creating...
local_file.configs["greeting"]: Creating...
local_file.configs["reminder"]: Creating...
local_file.configs["farewell"]: Creation complete after 0s
local_file.configs["greeting"]: Creation complete after 0s
local_file.configs["reminder"]: Creation complete after 0s

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

### Step 12 — Verify all files

```bash
for f in greeting farewell reminder; do
  echo "=== $f ==="
  cat "/tmp/$f.txt"
  echo
done
```

```
=== greeting ===
  File: greeting
  Message: Hello Folks of MassMutual
  Team: Alice, Bob, Charlie
  Timestamp enabled: true

=== farewell ===
  File: farewell
  Message: Hello Folks of MassMutual
  Team: Alice, Bob, Charlie
  Timestamp enabled: true

=== reminder ===
  File: reminder
  Message: Hello Folks of MassMutual
  Team: Alice, Bob, Charlie
  Timestamp enabled: true
```

### Step 13 — List resources in state

```bash
terraform state list
```

```
local_file.configs["farewell"]
local_file.configs["greeting"]
local_file.configs["reminder"]
```

> With `for_each`, each resource is keyed by name — not by index number. This is important: if you remove "farewell" from the map, ONLY that file is destroyed. The others are untouched.

---

## Part 6 — Outputs

### Step 14 — Create outputs.tf

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

### Step 15 — Apply to see outputs

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

### Step 16 — Query outputs

```bash
# All outputs
terraform output

# Specific output
terraform output file_count
```

```
3
```

```bash
# JSON format
terraform output -json file_paths
```

```json
{"farewell":"/tmp/farewell.txt","greeting":"/tmp/greeting.txt","reminder":"/tmp/reminder.txt"}
```

---

## Part 7 — Sensitive Files

### Step 17 — Add a sensitive file resource

Add to `main.tf`:

```bash
cat >> main.tf << 'EOF'

resource "local_sensitive_file" "secret" {
  filename = "/tmp/secret.env"
  content  = "DB_PASSWORD=super_s3cret_p@ssw0rd"
}

output "secret_path" {
  value     = local_sensitive_file.secret.filename
  sensitive = true
}
EOF
```

### Step 18 — Apply and observe

```bash
terraform apply -auto-approve
```

```
local_sensitive_file.secret: Creating...
local_sensitive_file.secret: Creation complete after 0s [id=...]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

file_count = 3
file_paths = { ... }
secret_path = <sensitive>
team_list = [ ... ]
```

> Notice `secret_path = <sensitive>` — Terraform hides it in output. The file still exists on disk:

```bash
cat /tmp/secret.env
```

```
DB_PASSWORD=super_s3cret_p@ssw0rd
```

> `sensitive = true` hides values from terminal output and plan diffs — but NOT from the state file. State always has the real value.

---

## Part 8 — Variable Validation

### Step 19 — Add validation to a variable

Add to `variables.tf`:

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

### Step 20 — Test with an invalid value

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

> Validation catches bad input BEFORE Terraform touches any resources. Always validate.

```bash
terraform plan -var='environment=prod'
```

```
No changes. Your infrastructure matches the configuration.
```

---

## Part 9 — State Inspection

### Step 21 — Explore what Terraform tracks

```bash
terraform state list
```

```
local_file.configs["farewell"]
local_file.configs["greeting"]
local_file.configs["reminder"]
local_sensitive_file.secret
```

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

---

## Part 10 — Clean Up

```bash
terraform destroy -auto-approve
```

```
local_sensitive_file.secret: Destroying...
local_file.configs["reminder"]: Destroying...
local_file.configs["greeting"]: Destroying...
local_file.configs["farewell"]: Destroying...
...

Destroy complete! Resources: 4 destroyed.
```

```bash
# Verify files are gone
ls /tmp/greeting.txt /tmp/farewell.txt /tmp/reminder.txt /tmp/secret.env 2>&1
```

```
ls: cannot access '/tmp/greeting.txt': No such file or directory
ls: cannot access '/tmp/farewell.txt': No such file or directory
ls: cannot access '/tmp/reminder.txt': No such file or directory
ls: cannot access '/tmp/secret.env': No such file or directory
```

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| `variable` | Parameterize configs (string, number, bool, list, map) |
| `terraform.tfvars` | Set variable values in a file |
| `-var` flag | Override from CLI |
| `TF_VAR_*` | Override from environment |
| Precedence | default < tfvars < -var-file < -var < TF_VAR_ |
| `for_each` | Create multiple resources from a map |
| `each.key` / `each.value` | Access current iteration |
| `output` | Expose values after apply |
| `sensitive` | Hide values in terminal (not in state!) |
| `validation` | Catch bad input before apply |
| `local_sensitive_file` | File with hidden content in plans |
| `terraform state list/show` | Inspect what Terraform manages |

> **Next:** Proceed to **003** to learn the Random provider, resource chaining, and `count`.
