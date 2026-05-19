# 006 — Outputs & the terraform output Command (Live Demo)

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~15 minutes

---

## Concept

After Terraform creates resources, you often need to **see the results** — a generated password, an IP address, a random value. That's what `output` blocks do. They display values after `terraform apply` and can be queried anytime with `terraform output`.

```
┌──────────────────────────────────────────────────────────┐
│                                                          │
│  resource creates something                              │
│       │                                                  │
│       ▼                                                  │
│  output block captures a value from the resource         │
│       │                                                  │
│       ▼                                                  │
│  terraform apply   → shows it at the end                 │
│  terraform output  → query it anytime after apply        │
│  terraform refresh → re-reads real state + shows outputs │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### Why Outputs Matter

| Without Outputs | With Outputs |
|----------------|-------------|
| Have to dig through state file | Values shown after every apply |
| Can't pass data to other modules | Outputs are how modules share data |
| Can't use in scripts/CI | `terraform output -raw` feeds into bash |
| No visibility into what was created | Clear summary of results |

---

## Step 1 — Create a fresh project

```bash
mkdir -p ~/tf_output_demo
cd ~/tf_output_demo
```

---

## Step 2 — Start WITHOUT an output block

```bash
cat > main.tf << 'EOF'
resource "random_string" "datagen" {
  length = 10
}
EOF
```

```bash
terraform init
```

```
- Installing hashicorp/random v3.5.1...
- Installed hashicorp/random v3.5.1 (signed by HashiCorp)

Terraform has been successfully initialized!
```

```bash
terraform apply
```

Type `yes`:

```
random_string.datagen: Creating...
random_string.datagen: Creation complete after 0s [id=hHGHHl@c0m]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

> The random string `hHGHHl@c0m` was generated — but where is it? It's buried in the state file. There's no easy way to see it. We need an **output**.

---

## Step 3 — Add an output block

```bash
cat > main.tf << 'EOF'
resource "random_string" "datagen" {
  length = 10
}

output "myrandstring" {
  value = random_string.datagen.result
}
EOF
```

### What does this mean?

```
output "myrandstring" {
  │       │
  │       └── Name: how you query it (terraform output myrandstring)
  │
  value = random_string.datagen.result
          │               │       │
          │               │       └── Attribute: the generated string
          │               └── Resource name
          └── Resource type
}
```

---

## Step 4 — Apply — output appears at the end

```bash
terraform apply
```

Type `yes`:

```
random_string.datagen: Refreshing state... [id=hHGHHl@c0m]

Changes to Outputs:
  + myrandstring = "hHGHHl@c0m"

You can apply this plan to save these new output values to the Terraform state,
without changing any real infrastructure.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

myrandstring = "hHGHHl@c0m"
```

> **Key observations:**
> - No resources were created/changed (0 added, 0 changed) — the random string already existed
> - `Changes to Outputs: + myrandstring` — a NEW output was registered
> - The value `hHGHHl@c0m` now shows at the bottom of every apply

---

## Step 5 — Apply again — output persists

```bash
terraform apply
```

```
random_string.datagen: Refreshing state... [id=hHGHHl@c0m]

No changes. Your infrastructure matches the configuration.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

myrandstring = "hHGHHl@c0m"
```

> Same output every time. Outputs are stored in state alongside resources.

---

## Step 6 — terraform output command

You don't need to run `apply` to see outputs. Use `terraform output`:

```bash
terraform output
```

```
myrandstring = "hHGHHl@c0m"
```

### Query a specific output:

```bash
terraform output myrandstring
```

```
"hHGHHl@c0m"
```

### Raw value (no quotes — useful for scripts):

```bash
terraform output -raw myrandstring
```

```
hHGHHl@c0m
```

### JSON format (useful for parsing):

```bash
terraform output -json
```

```json
{
  "myrandstring": {
    "value": "hHGHHl@c0m",
    "type": "string"
  }
}
```

> **Use in scripts:**
> ```bash
> MY_VALUE=$(terraform output -raw myrandstring)
> echo "The value is: $MY_VALUE"
> ```

---

## Step 7 — terraform refresh

`terraform refresh` re-reads the real state of resources and updates the state file. It also shows outputs:

```bash
terraform refresh
```

```
random_string.datagen: Refreshing state... [id=hHGHHl@c0m]

Outputs:

myrandstring = "hHGHHl@c0m"
```

> `refresh` is like a read-only sync — it checks if real resources still match state. It does NOT create or destroy anything.

> **Note:** `terraform refresh` is deprecated in newer versions. Use `terraform apply -refresh-only` instead. But it still works and you'll see it in older tutorials.

---

## Step 8 — Add a second resource with its own output

```bash
cat > main.tf << 'EOF'
resource "random_string" "datagen" {
  length = 10
}

resource "random_integer" "idnum" {
  min = 10
  max = 200
}

output "myrandstring" {
  value = random_string.datagen.result
}

output "randint" {
  value = random_integer.idnum.result
}
EOF
```

---

## Step 9 — Apply — only new resource created

```bash
terraform apply
```

Type `yes`:

```
random_string.datagen: Refreshing state... [id=hHGHHl@c0m]

  # random_integer.idnum will be created
  + resource "random_integer" "idnum" {
      + id     = (known after apply)
      + max    = 200
      + min    = 10
      + result = (known after apply)
    }

Plan: 1 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + randint = (known after apply)

random_integer.idnum: Creating...
random_integer.idnum: Creation complete after 0s [id=87]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

myrandstring = "hHGHHl@c0m"
randint = 87
```

> **Both outputs now show** — the existing `myrandstring` and the new `randint`.

---

## Step 10 — Verify with terraform output

```bash
terraform output
```

```
myrandstring = "hHGHHl@c0m"
randint = 87
```

### Query individually:

```bash
terraform output myrandstring
```

```
"hHGHHl@c0m"
```

```bash
terraform output randint
```

```
87
```

---

## Step 11 — Output with description

Add descriptions so others know what the output means:

```bash
cat > main.tf << 'EOF'
resource "random_string" "datagen" {
  length = 10
}

resource "random_integer" "idnum" {
  min = 10
  max = 200
}

output "myrandstring" {
  description = "A random 10-character string"
  value       = random_string.datagen.result
}

output "randint" {
  description = "A random integer between 10 and 200"
  value       = random_integer.idnum.result
}
EOF
```

```bash
terraform apply -auto-approve
```

```
Outputs:

myrandstring = "hHGHHl@c0m"
randint = 87
```

> Descriptions don't show in terminal output — but they show in `terraform-docs` and module registry pages. Always add them.

---

## Step 12 — Multiple output types

Outputs aren't just strings. They can be any type:

```bash
cat > main.tf << 'EOF'
resource "random_string" "datagen" {
  length = 10
}

resource "random_integer" "idnum" {
  min = 10
  max = 200
}

output "myrandstring" {
  description = "A random 10-character string"
  value       = random_string.datagen.result
}

output "randint" {
  description = "A random integer between 10 and 200"
  value       = random_integer.idnum.result
}

output "all_info" {
  description = "Everything as a map"
  value = {
    random_string  = random_string.datagen.result
    random_integer = random_integer.idnum.result
    combined       = "${random_string.datagen.result}-${random_integer.idnum.result}"
  }
}

output "is_high" {
  description = "Whether the random integer is above 100"
  value       = random_integer.idnum.result > 100
}
EOF
```

```bash
terraform apply -auto-approve
```

```
Outputs:

all_info = {
  "combined" = "hHGHHl@c0m-87"
  "random_integer" = 87
  "random_string" = "hHGHHl@c0m"
}
is_high      = false
myrandstring = "hHGHHl@c0m"
randint      = 87
```

> Outputs can be: **strings**, **numbers**, **bools**, **maps**, **lists** — anything Terraform can compute.

---

## Step 13 — Clean Up

```bash
terraform destroy -auto-approve
```

```
Destroy complete! Resources: 2 destroyed.
```

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| `output` block | Expose values after apply |
| `value = resource.name.attribute` | Reference any resource attribute |
| `description` | Document what the output means |
| `terraform output` | Query outputs anytime (no apply needed) |
| `terraform output -raw NAME` | Get raw value (no quotes, for scripts) |
| `terraform output -json` | Get all outputs as JSON |
| `terraform refresh` | Re-read state + show outputs (deprecated) |
| Output types | string, number, bool, map, list — any type |
| `Changes to Outputs: +` | New output registered (no infra change) |

### When to use outputs

```
Local dev       → see generated values after apply
Modules         → pass data between modules (output → input)
CI/CD scripts   → terraform output -raw my_ip → feed into deploy
Remote state    → terraform_remote_state reads outputs from another project
```

> **Next:** Proceed to **007** for resource chaining, keepers, count, and for_each with the random provider.
