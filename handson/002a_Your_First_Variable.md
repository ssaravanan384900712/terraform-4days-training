# 002a — Your First Variable & Passing Values

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~10 minutes

---

## Concept

In 001 we hardcoded everything. Real Terraform code uses **variables** to make configs reusable. This lab teaches how to declare a variable, reference it, and override via `-var` CLI flag.

```
┌────────────────────────────────────────────────────────┐
│                                                        │
│  variables.tf  ──►  main.tf  ──►  resource created     │
│  (declare)          (use var.X)                        │
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

## Summary

| Concept | What You Learned |
|---------|-----------------|
| `variable` block | Declare inputs with type and default |
| `var.name` | Reference a variable in resources |
| `-var` flag | Override from command line |

> **Next:** Proceed to **003** for tfvars, env vars, auto.tfvars, -var-file, and the full precedence order.
