# 002a — Your First Variable & Passing Values

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~10 minutes

---

## Concept

In 001 we hardcoded everything. Real Terraform code uses **variables** to make configs reusable. This lab teaches how to declare a variable, reference it, and pass values 3 different ways.

```
┌────────────────────────────────────────────────────────┐
│                                                        │
│  variables.tf  ──►  main.tf  ──►  resource created     │
│  (declare)          (use var.X)                        │
│                                                        │
│  3 ways to set a variable's value:                     │
│    1. terraform.tfvars file                            │
│    2. -var='key=value' CLI flag                        │
│    3. TF_VAR_name environment variable                 │
│                                                        │
└────────────────────────────────────────────────────────┘
```

---

## Step 1 — Create a fresh project

```bash
mkdir -p ~/tf_works/002_variables
cd ~/tf_works/002_variables
```

---

## Step 2 — Start with a hardcoded value

```bash
cat > main.tf << 'EOF'
resource "local_file" "greeting" {
  content  = "Hello Folks of MassMutual"
  filename = "/tmp/greeting.txt"
}
EOF
```

This works, but the content is stuck. What if we want to change the message without editing main.tf?

---

## Step 3 — Extract into a variable

Replace `main.tf`:

```bash
cat > main.tf << 'EOF'
resource "local_file" "greeting" {
  content  = var.message
  filename = "/tmp/greeting.txt"
}
EOF
```

Create `variables.tf`:

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
  │         └── Name: reference it as var.message
  │
  description = "..."   ← Human-readable help text
  type        = string  ← Must be a string
  default     = "..."   ← Used if no value provided
}
```

## Step 4 — Init and apply

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

> The `default` value was used since we didn't provide one.

---

## Step 5 — Override via CLI flag (-var)

```bash
terraform apply -auto-approve -var='message=Hello from the CLI!'
```

```
  # local_file.greeting must be replaced
-/+ resource "local_file" "greeting" {
      ~ content = "Hello Folks of MassMutual" -> "Hello from the CLI!"
      ...
    }

Apply complete! Resources: 1 added, 0 changed, 1 destroyed.
```

```bash
cat /tmp/greeting.txt
```

```
Hello from the CLI!
```

> `-var` overrides the default. Notice `-/+` (replace) — file destroyed and recreated because content changed.

---

## Step 6 — Override via terraform.tfvars

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

---

## Step 7 — Override via environment variable

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

---

## Variable Precedence (lowest to highest)

```
1. default in variables.tf     ← lowest priority
2. terraform.tfvars file
3. *.auto.tfvars files
4. -var-file="custom.tfvars"
5. -var='key=value' CLI flag
6. TF_VAR_name environment var  ← highest priority
```

Clean up for next lab:

```bash
rm terraform.tfvars
```

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| `variable` block | Declare inputs with type and default |
| `var.name` | Reference a variable in resources |
| `terraform.tfvars` | Auto-loaded variable values file |
| `-var` flag | Override from command line |
| `TF_VAR_*` | Override from environment |
| Precedence | default < tfvars < -var < TF_VAR_ |

> **Next:** Proceed to **002b** for variable types and multiple resources with `for_each`.
