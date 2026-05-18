# 003 — tfvars, Environment Variables & Variable Precedence

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~15 minutes

---

## Concept

Terraform offers **6 ways** to set a variable's value. In real projects, you'll use different methods for different situations — local dev vs CI/CD vs per-environment configs. Understanding **which one wins** (precedence) is critical.

```
┌─────────────────────────────────────────────────────────┐
│         Variable Value Sources (lowest → highest)        │
│                                                         │
│  1. default in variable block        ← fallback         │
│  2. terraform.tfvars                 ← auto-loaded      │
│  3. *.auto.tfvars (alphabetical)     ← auto-loaded      │
│  4. -var-file="custom.tfvars"        ← explicit file    │
│  5. -var='key=value'                 ← CLI override     │
│  6. TF_VAR_name                      ← env variable     │
│                                                         │
│  Higher number WINS over lower number                   │
└─────────────────────────────────────────────────────────┘
```

---

## Prerequisites

Continue from 002a (or recreate):

```bash
cd ~/tf_works/002_variables
```

Make sure you have these files from 002a:

```bash
cat > variables.tf << 'EOF'
variable "message" {
  description = "The greeting message to write"
  type        = string
  default     = "Hello Folks of MassMutual"
}
EOF

cat > main.tf << 'EOF'
resource "local_file" "greeting" {
  content  = var.message
  filename = "/tmp/greeting.txt"
}
EOF

terraform init
```

> **Note:** We are NOT using outputs yet — that's a separate topic in 004. We verify values by reading the file directly with `cat`.

---

## Part 1 — terraform.tfvars (Auto-Loaded)

### Step 1 — Apply with default value first

```bash
terraform apply -auto-approve
cat /tmp/greeting.txt
```

```
Hello Folks of MassMutual
```

> The `default` from variables.tf was used.

### Step 2 — Create terraform.tfvars

```bash
cat > terraform.tfvars << 'EOF'
message = "Hello from terraform.tfvars!"
EOF
```

### Step 3 — Apply — tfvars overrides the default

```bash
terraform apply -auto-approve
cat /tmp/greeting.txt
```

```
Hello from terraform.tfvars!
```

> **`terraform.tfvars` is auto-loaded** — Terraform looks for this exact filename and loads it automatically. No flag needed.

### Step 4 — Add a second variable to terraform.tfvars

```bash
cat >> variables.tf << 'EOF'

variable "author" {
  description = "Who wrote this config"
  type        = string
  default     = "unknown"
}
EOF

cat > main.tf << 'EOF'
resource "local_file" "greeting" {
  content  = "${var.message}\nAuthor: ${var.author}"
  filename = "/tmp/greeting.txt"
}
EOF

cat > terraform.tfvars << 'EOF'
message = "Multi-var demo from tfvars"
author  = "Saravanan"
EOF
```

```bash
terraform apply -auto-approve
cat /tmp/greeting.txt
```

```
Multi-var demo from tfvars
Author: Saravanan
```

---

## Part 2 — *.auto.tfvars (Also Auto-Loaded)

### Step 5 — Create an auto.tfvars file

Any file ending in `.auto.tfvars` is automatically loaded:

```bash
cat > team.auto.tfvars << 'EOF'
author = "Team Platform"
EOF
```

### Step 6 — Apply — auto.tfvars overrides terraform.tfvars

```bash
terraform apply -auto-approve
cat /tmp/greeting.txt
```

```
Multi-var demo from tfvars
Author: Team Platform
```

> `author` came from `team.auto.tfvars` (overrode terraform.tfvars). `message` still from terraform.tfvars.

### Step 7 — Multiple auto.tfvars files (alphabetical order)

```bash
cat > aaa.auto.tfvars << 'EOF'
author = "From aaa.auto.tfvars"
EOF

cat > zzz.auto.tfvars << 'EOF'
author = "From zzz.auto.tfvars"
EOF
```

```bash
terraform apply -auto-approve
cat /tmp/greeting.txt
```

```
Multi-var demo from tfvars
Author: From zzz.auto.tfvars
```

> Multiple `*.auto.tfvars` load **alphabetically**. `zzz` loads last and wins.

```bash
rm aaa.auto.tfvars zzz.auto.tfvars team.auto.tfvars
```

---

## Part 3 — -var-file (Explicit File)

### Step 8 — Create per-environment tfvars files

```bash
cat > dev.tfvars << 'EOF'
message = "Hello from DEV environment"
author  = "Dev Team"
EOF

cat > staging.tfvars << 'EOF'
message = "Hello from STAGING environment"
author  = "QA Team"
EOF

cat > prod.tfvars << 'EOF'
message = "Hello from PRODUCTION"
author  = "Platform Team"
EOF
```

### Step 9 — Apply with -var-file for each environment

```bash
terraform apply -auto-approve -var-file="dev.tfvars"
cat /tmp/greeting.txt
```

```
Hello from DEV environment
Author: Dev Team
```

```bash
terraform apply -auto-approve -var-file="staging.tfvars"
cat /tmp/greeting.txt
```

```
Hello from STAGING environment
Author: QA Team
```

```bash
terraform apply -auto-approve -var-file="prod.tfvars"
cat /tmp/greeting.txt
```

```
Hello from PRODUCTION
Author: Platform Team
```

> **This is the standard pattern** for multiple environments:

```
project/
├── main.tf              ← Same code
├── variables.tf         ← Same variables
├── dev.tfvars           ← Dev values
├── staging.tfvars       ← Staging values
└── prod.tfvars          ← Prod values

terraform apply -var-file="dev.tfvars"
terraform apply -var-file="prod.tfvars"
```

### Step 10 — -var-file overrides terraform.tfvars

```bash
terraform apply -auto-approve -var-file="prod.tfvars"
cat /tmp/greeting.txt
```

```
Hello from PRODUCTION
Author: Platform Team
```

> `-var-file` wins over `terraform.tfvars`. Higher precedence.

---

## Part 4 — -var CLI Flag

### Step 11 — Override with -var

```bash
terraform apply -auto-approve -var-file="prod.tfvars" -var='message=CLI wins!'
cat /tmp/greeting.txt
```

```
CLI wins!
Author: Platform Team
```

> `message` from `-var` beat `-var-file`. `author` still from prod.tfvars.

### Step 12 — Multiple -var flags

```bash
terraform apply -auto-approve \
  -var='message=Both overridden' \
  -var='author=CLI Author'
cat /tmp/greeting.txt
```

```
Both overridden
Author: CLI Author
```

---

## Part 5 — TF_VAR_ Environment Variables

### Step 13 — Set via environment

```bash
export TF_VAR_message="Hello from TF_VAR environment!"
export TF_VAR_author="Env Author"
```

### Step 14 — Env var wins over EVERYTHING

```bash
terraform apply -auto-approve -var-file="prod.tfvars" -var='message=CLI attempt'
cat /tmp/greeting.txt
```

```
Hello from TF_VAR environment!
Author: Env Author
```

> Even `-var-file` AND `-var` were set — `TF_VAR_*` still won. **Highest precedence.**

### Step 15 — Clean up env vars

```bash
unset TF_VAR_message
unset TF_VAR_author
```

---

## Part 6 — The Complete Precedence Peel-Off Test

Set up ALL sources at once, then remove one at a time:

### Step 16 — All 5 sources active

```bash
cat > override.auto.tfvars << 'EOF'
message = "From auto.tfvars"
EOF

export TF_VAR_message="ENV WINS"
terraform apply -auto-approve -var-file="prod.tfvars" -var='message=CLI attempt'
cat /tmp/greeting.txt
```

```
ENV WINS
```

### Step 17 — Remove env var

```bash
unset TF_VAR_message
terraform apply -auto-approve -var-file="prod.tfvars" -var='message=CLI attempt'
cat /tmp/greeting.txt
```

```
CLI attempt
```

### Step 18 — Remove -var (just use -var-file)

```bash
terraform apply -auto-approve -var-file="prod.tfvars"
cat /tmp/greeting.txt
```

```
Hello from PRODUCTION
```

### Step 19 — Remove -var-file (just auto-loaded files)

```bash
terraform apply -auto-approve
cat /tmp/greeting.txt
```

```
From auto.tfvars
```

### Step 20 — Remove auto.tfvars

```bash
rm override.auto.tfvars
terraform apply -auto-approve
cat /tmp/greeting.txt
```

```
Multi-var demo from tfvars
```

### Step 21 — Remove terraform.tfvars (back to default)

```bash
rm terraform.tfvars
terraform apply -auto-approve
cat /tmp/greeting.txt
```

```
Hello Folks of MassMutual
```

> Back to the default! Each layer peeled off proves the precedence order.

---

## Precedence Summary

```
TF_VAR_message="ENV"              ← 6. HIGHEST
    ▼ (if not set)
-var='message=CLI'                ← 5.
    ▼ (if not set)
-var-file="prod.tfvars"           ← 4.
    ▼ (if not set)
*.auto.tfvars                     ← 3. (alphabetical, last wins)
    ▼ (if not set)
terraform.tfvars                  ← 2. (auto-loaded)
    ▼ (if not set)
default = "..." in variables.tf   ← 1. LOWEST
```

## When to Use What

| Method | Best For |
|--------|----------|
| `default` | Sensible fallback |
| `terraform.tfvars` | Local dev defaults |
| `*.auto.tfvars` | Team-shared overrides |
| `-var-file` | Per-environment deploys (dev/staging/prod) |
| `-var` | One-off overrides, quick testing |
| `TF_VAR_*` | CI/CD pipelines, secrets from vault |

---

## Clean Up

```bash
rm -f dev.tfvars staging.tfvars prod.tfvars
terraform destroy -auto-approve
```

> **Next:** Proceed to **004** for Terraform outputs — how to expose and query values after apply.
