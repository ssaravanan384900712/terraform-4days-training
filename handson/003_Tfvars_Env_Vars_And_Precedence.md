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

output "current_message" {
  value = var.message
}
EOF

terraform init
```

---

## Part 1 — terraform.tfvars (Auto-Loaded)

### Step 1 — Apply with default value first

```bash
terraform apply -auto-approve
```

```
Outputs:

current_message = "Hello Folks of MassMutual"
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
```

```
  # local_file.greeting must be replaced
-/+ resource "local_file" "greeting" {
      ~ content = "Hello Folks of MassMutual" -> "Hello from terraform.tfvars!"
      ...
    }

Apply complete! Resources: 1 added, 0 changed, 1 destroyed.

Outputs:

current_message = "Hello from terraform.tfvars!"
```

```bash
cat /tmp/greeting.txt
```

```
Hello from terraform.tfvars!
```

> **`terraform.tfvars` is auto-loaded** — Terraform looks for this exact filename and loads it automatically. No flag needed.

### Step 4 — tfvars with multiple variables

```bash
cat > terraform.tfvars << 'EOF'
message = "Multi-var demo from tfvars"
EOF
```

Add another variable to `variables.tf`:

```bash
cat > variables.tf << 'EOF'
variable "message" {
  description = "The greeting message"
  type        = string
  default     = "Hello Folks of MassMutual"
}

variable "author" {
  description = "Who wrote this config"
  type        = string
  default     = "unknown"
}
EOF
```

Update `terraform.tfvars`:

```bash
cat > terraform.tfvars << 'EOF'
message = "Multi-var demo from tfvars"
author  = "Saravanan"
EOF
```

Update `main.tf` to use both:

```bash
cat > main.tf << 'EOF'
resource "local_file" "greeting" {
  content  = "${var.message}\nAuthor: ${var.author}"
  filename = "/tmp/greeting.txt"
}

output "current_message" {
  value = var.message
}

output "current_author" {
  value = var.author
}
EOF
```

```bash
terraform apply -auto-approve
```

```
Outputs:

current_author  = "Saravanan"
current_message = "Multi-var demo from tfvars"
```

```bash
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
```

```
Outputs:

current_author  = "Team Platform"
current_message = "Multi-var demo from tfvars"
```

> `author` came from `team.auto.tfvars` (overrode `terraform.tfvars`). `message` still from `terraform.tfvars`.

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
```

```
Outputs:

current_author = "From zzz.auto.tfvars"
```

> Multiple `*.auto.tfvars` are loaded **alphabetically**. `zzz` loads last and wins over `aaa` and `team`.

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

### Step 9 — Apply with -var-file

```bash
terraform apply -auto-approve -var-file="dev.tfvars"
```

```
Outputs:

current_author  = "Dev Team"
current_message = "Hello from DEV environment"
```

```bash
terraform apply -auto-approve -var-file="staging.tfvars"
```

```
Outputs:

current_author  = "QA Team"
current_message = "Hello from STAGING environment"
```

```bash
terraform apply -auto-approve -var-file="prod.tfvars"
```

```
Outputs:

current_author  = "Platform Team"
current_message = "Hello from PRODUCTION"
```

> **This is the standard pattern** for managing multiple environments with Terraform. Same code, different `.tfvars` file per env.

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

Both `terraform.tfvars` and `-var-file` set `message`. Which wins?

```bash
terraform apply -auto-approve -var-file="prod.tfvars"
```

```
current_message = "Hello from PRODUCTION"
```

> `-var-file` wins over `terraform.tfvars`. Higher precedence.

---

## Part 4 — -var CLI Flag

### Step 11 — Override everything with -var

```bash
terraform apply -auto-approve -var-file="prod.tfvars" -var='message=CLI wins over everything!'
```

```
Outputs:

current_author  = "Platform Team"
current_message = "CLI wins over everything!"
```

> `-var` overrides `-var-file` which overrides `terraform.tfvars`. `author` came from `prod.tfvars`, but `message` came from `-var`.

### Step 12 — Multiple -var flags

```bash
terraform apply -auto-approve \
  -var='message=Both overridden' \
  -var='author=CLI Author'
```

```
Outputs:

current_author  = "CLI Author"
current_message = "Both overridden"
```

---

## Part 5 — TF_VAR_ Environment Variables

### Step 13 — Set via environment

```bash
export TF_VAR_message="Hello from TF_VAR environment!"
export TF_VAR_author="Env Author"
```

### Step 14 — Apply — env var wins over EVERYTHING

```bash
terraform apply -auto-approve -var-file="prod.tfvars" -var='message=CLI attempt'
```

```
Outputs:

current_author  = "Env Author"
current_message = "Hello from TF_VAR environment!"
```

> Even though we used `-var-file` AND `-var`, the `TF_VAR_*` environment variable won. It has the **highest precedence**.

### Step 15 — Verify and clean up env vars

```bash
echo "TF_VAR_message = $TF_VAR_message"
echo "TF_VAR_author  = $TF_VAR_author"

unset TF_VAR_message
unset TF_VAR_author
```

> **When to use TF_VAR_:**
> - CI/CD pipelines (GitHub Actions secrets → env vars)
> - Docker containers
> - Temporary overrides without editing files

---

## Part 6 — The Complete Precedence Test

### Step 16 — All 5 sources active at once

Set up everything simultaneously:

```bash
# 1. default is in variables.tf: "Hello Folks of MassMutual"
# 2. terraform.tfvars already exists
# 3. Create an auto.tfvars
cat > override.auto.tfvars << 'EOF'
message = "From auto.tfvars"
EOF
# 4. We'll use -var-file
# 5. We'll use -var
# 6. We'll use TF_VAR_
export TF_VAR_message="ENV WINS"
```

```bash
terraform apply -auto-approve -var-file="prod.tfvars" -var='message=CLI attempt'
```

```
Outputs:

current_message = "ENV WINS"
```

### Step 17 — Remove env var, test again

```bash
unset TF_VAR_message
terraform apply -auto-approve -var-file="prod.tfvars" -var='message=CLI attempt'
```

```
current_message = "CLI attempt"
```

### Step 18 — Remove -var, test again

```bash
terraform apply -auto-approve -var-file="prod.tfvars"
```

```
current_message = "Hello from PRODUCTION"
```

### Step 19 — Remove -var-file, test again

```bash
terraform apply -auto-approve
```

```
current_message = "From auto.tfvars"
```

### Step 20 — Remove auto.tfvars, test again

```bash
rm override.auto.tfvars
terraform apply -auto-approve
```

```
current_message = "Multi-var demo from tfvars"
```

### Step 21 — Remove terraform.tfvars, test again

```bash
rm terraform.tfvars
terraform apply -auto-approve
```

```
current_message = "Hello Folks of MassMutual"
```

> Back to the default! We peeled off each layer one by one, proving the precedence order.

---

## Precedence Summary Diagram

```
TF_VAR_message="ENV"              ← 6. HIGHEST (wins over all)
    │
    ▼ (if not set)
-var='message=CLI'                ← 5.
    │
    ▼ (if not set)
-var-file="prod.tfvars"           ← 4.
    │
    ▼ (if not set)
*.auto.tfvars                     ← 3. (alphabetical, last wins)
    │
    ▼ (if not set)
terraform.tfvars                  ← 2. (auto-loaded)
    │
    ▼ (if not set)
default = "..." in variables.tf   ← 1. LOWEST (fallback)
```

---

## When to Use What

| Method | Best For |
|--------|----------|
| `default` | Sensible fallback, works out of the box |
| `terraform.tfvars` | Local development defaults |
| `*.auto.tfvars` | Team-shared overrides (committed to git) |
| `-var-file` | Per-environment deploys (dev.tfvars, prod.tfvars) |
| `-var` | One-off overrides, quick testing |
| `TF_VAR_*` | CI/CD pipelines, secrets from vault/env |

---

## Clean Up

```bash
rm -f dev.tfvars staging.tfvars prod.tfvars
terraform destroy -auto-approve
```

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| `terraform.tfvars` | Auto-loaded, no flag needed |
| `*.auto.tfvars` | Auto-loaded, alphabetical order, last wins |
| `-var-file` | Explicit file, overrides auto-loaded |
| `-var` | CLI flag, overrides files |
| `TF_VAR_*` | Environment variable, highest precedence |
| Precedence | default < tfvars < auto.tfvars < -var-file < -var < TF_VAR_ |
| Per-env pattern | Same code + different .tfvars per environment |

> **Next:** Proceed to **004** for the Random provider, resource chaining, and count/for_each.
