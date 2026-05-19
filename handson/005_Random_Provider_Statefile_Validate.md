# 005 — Random Provider, State File & Validate (Live Demo)

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~20 minutes

---

## Concept

This lab introduces the **random provider** — a second provider that generates random values stored in state. Along the way you'll learn `terraform validate` (catch syntax errors before plan), see how the **state file** tracks resources, and understand **forces replacement** vs **in-place update**.

```
┌──────────────────────────────────────────────────────────┐
│                                                          │
│  random_string   → generates "D#u2Im" → stored in state │
│  random_integer  → generates 58       → stored in state │
│                                                          │
│  Key lessons:                                            │
│    1. terraform validate catches syntax errors early     │
│    2. State preserves random values (idempotent)         │
│    3. Changing length/min/max → forces replacement       │
│    4. Adding a resource → only that one created          │
│    5. Removing a resource → only that one destroyed      │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

---

## Step 1 — Create a fresh project

```bash
mkdir -p ~/tf_random_demo
cd ~/tf_random_demo
```

---

## Step 2 — Write a random_string resource

```bash
cat > main.tf << 'EOF'
resource "random_string" "datagen" {
  length = 6
}
EOF
```

```bash
cat main.tf
```

```hcl
resource "random_string" "datagen" {
  length = 6
}
```

---

## Step 3 — Initialize

```bash
terraform init
```

```
- Installing hashicorp/random v3.5.1...
- Installed hashicorp/random v3.5.1 (signed by HashiCorp)

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above.

Terraform has been successfully initialized!
```

```bash
ls -a
```

```
.  ..  .terraform  .terraform.lock.hcl  main.tf
```

---

## Step 4 — terraform validate (syntax check)

### Valid config first:

```bash
terraform validate
```

```
Success! The configuration is valid.
```

> `terraform validate` checks HCL syntax without calling any API. It's fast and safe — run it before every plan.

### Now break the syntax intentionally:

Edit `main.tf` — remove the opening quote from `"random_string"`:

```bash
cat > main.tf << 'EOF'
resource random_string" "datagen" {
  length = 6
}
EOF
```

```bash
terraform validate
```

```
╷
│ Error: Extraneous label for resource
│
│   on main.tf line 1:

│ Error: Invalid string literal
│
│   on main.tf line 1:
│    1: resource random_string" "datagen" {
│
│ This item is not valid in a string literal.
╵
```

> Terraform caught the missing quote! The error points to **exactly which line** has the problem. This is why you always validate before plan.

### Fix it:

```bash
cat > main.tf << 'EOF'
resource "random_string" "datagen" {
  length = 6
}
EOF
```

```bash
terraform validate
```

```
Success! The configuration is valid.
```

> **Best practice:** Run `terraform validate` → `terraform plan` → `terraform apply`. Validate catches typos instantly without waiting for a provider API call.

---

## Step 5 — Plan and Apply

### Plan:

```bash
terraform plan
```

```
  # random_string.datagen will be created
  + resource "random_string" "datagen" {
      + id          = (known after apply)
      + length      = 6
      + lower       = true
      + min_lower   = 0
      + min_numeric = 0
      + min_special = 0
      + min_upper   = 0
      + number      = true
      + numeric     = true
      + result      = (known after apply)
      + special     = true
      + upper       = true
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

> Notice all the attributes: `lower`, `upper`, `numeric`, `special` default to `true`. The `result` is `(known after apply)` because the random value doesn't exist until Terraform creates it.

### Apply:

```bash
terraform apply
```

Type `yes`:

```
random_string.datagen: Creating...
random_string.datagen: Creation complete after 0s [id=D#u2Im]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

> The generated value is `D#u2Im` — 6 characters with upper, lower, numbers, and specials.

---

## Step 6 — State File Deep Dive

### Where is the random value stored?

```bash
ls -la terraform.tfstate
```

```
-rw-r--r-- 1 saravanans saravanans 1234 ... terraform.tfstate
```

```bash
cat terraform.tfstate | python3 -m json.tool
```

```json
{
    "version": 4,
    "terraform_version": "1.9.5",
    "serial": 1,
    "lineage": "...",
    "outputs": {},
    "resources": [
        {
            "mode": "managed",
            "type": "random_string",
            "name": "datagen",
            "provider": "provider[\"registry.terraform.io/hashicorp/random\"]",
            "instances": [
                {
                    "schema_version": 2,
                    "attributes": {
                        "id": "D#u2Im",
                        "length": 6,
                        "lower": true,
                        "result": "D#u2Im",
                        "special": true,
                        "upper": true
                    }
                }
            ]
        }
    ]
}
```

> **The state file is Terraform's memory.** The random value `D#u2Im` is stored here. That's how Terraform knows not to regenerate it on the next apply.

### State CLI:

```bash
terraform state list
```

```
random_string.datagen
```

```bash
terraform state show random_string.datagen
```

```
# random_string.datagen:
resource "random_string" "datagen" {
    id          = "D#u2Im"
    length      = 6
    lower       = true
    numeric     = true
    result      = "D#u2Im"
    special     = true
    upper       = true
}
```

---

## Step 7 — Idempotency Proof

```bash
terraform apply
```

```
random_string.datagen: Refreshing state... [id=D#u2Im]

No changes. Your infrastructure matches the configuration.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

Run it again:

```bash
terraform apply
```

```
No changes. Your infrastructure matches the configuration.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

> **Same value every time.** The random string was generated once and stored in state. Apply 100 times — still `D#u2Im`. This is idempotency.

---

## Step 8 — Forces Replacement (Change Length)

Change `length` from 6 to 10:

```bash
cat > main.tf << 'EOF'
resource "random_string" "datagen" {
  length = 10
}
EOF
```

```bash
terraform apply
```

```
random_string.datagen: Refreshing state... [id=D#u2Im]

  # random_string.datagen must be replaced
-/+ resource "random_string" "datagen" {
      ~ id          = "D#u2Im" -> (known after apply)
      ~ length      = 6 -> 10 # forces replacement
      ~ result      = "D#u2Im" -> (known after apply)
        # (9 unchanged attributes hidden)
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

Type `yes`:

```
random_string.datagen: Destroying... [id=D#u2Im]
random_string.datagen: Destruction complete after 0s
random_string.datagen: Creating...
random_string.datagen: Creation complete after 0s [id=]bHhiY64qd]

Apply complete! Resources: 1 added, 0 changed, 1 destroyed.
```

### What happened?

```
-/+  means "destroy and then create replacement"

~ length = 6 -> 10 # forces replacement
                      ^^^^^^^^^^^^^^^^^^^^
                      This attribute CANNOT be changed in-place.
                      The only way to change it is destroy + recreate.
```

> **forces replacement** = Terraform must destroy the old resource and create a new one. The random value changed from `D#u2Im` to `]bHhiY64qd` because it's a completely new resource.

> **This is the same behavior you'll see with AWS:** changing an EC2 AMI forces replacement (new instance), while changing tags is in-place.

---

## Step 9 — Adding a Second Resource

```bash
cat > main.tf << 'EOF'
resource "random_string" "datagen" {
  length = 10
}

resource "random_string" "datagen2" {
  length = 10
}
EOF
```

```bash
terraform apply
```

```
random_string.datagen: Refreshing state... [id=]bHhiY64qd]

  # random_string.datagen2 will be created
  + resource "random_string" "datagen2" {
      + id          = (known after apply)
      + length      = 10
      + result      = (known after apply)
      ...
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

Type `yes`:

```
random_string.datagen2: Creating...
random_string.datagen2: Creation complete after 0s [id=r}scqP*!KS]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

> **Only `datagen2` was created.** `datagen` was untouched — it already exists in state. Terraform only acts on the diff.

### Check state:

```bash
terraform state list
```

```
random_string.datagen
random_string.datagen2
```

> Two resources tracked.

---

## Step 10 — Removing a Resource from Code

Remove `datagen2` from main.tf:

```bash
cat > main.tf << 'EOF'
resource "random_string" "datagen" {
  length = 10
}
EOF
```

```bash
terraform apply
```

```
random_string.datagen2: Refreshing state... [id=r}scqP*!KS]
random_string.datagen: Refreshing state... [id=]bHhiY64qd]

  # random_string.datagen2 will be destroyed
  # (because random_string.datagen2 is not in configuration)
  - resource "random_string" "datagen2" {
      - id          = "r}scqP*!KS" -> null
      - length      = 10 -> null
      - result      = "r}scqP*!KS" -> null
      ...
    }

Plan: 0 to add, 0 to change, 1 to destroy.
```

Type `yes`:

```
random_string.datagen2: Destroying... [id=r}scqP*!KS]
random_string.datagen2: Destruction complete after 0s

Apply complete! Resources: 0 added, 0 changed, 1 destroyed.
```

> **Key insight:** Remove a resource from your `.tf` file → Terraform destroys it. The code IS the desired state. If something isn't in the code, it shouldn't exist.

```bash
terraform state list
```

```
random_string.datagen
```

> Only `datagen` remains.

---

## Step 11 — Adding random_integer

```bash
cat > main.tf << 'EOF'
resource "random_string" "datagen" {
  length = 10
}

resource "random_integer" "rint" {
  min = 10
  max = 100
}
EOF
```

```bash
terraform apply
```

```
  # random_integer.rint will be created
  + resource "random_integer" "rint" {
      + id     = (known after apply)
      + max    = 100
      + min    = 10
      + result = (known after apply)
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

Type `yes`:

```
random_integer.rint: Creating...
random_integer.rint: Creation complete after 0s [id=10]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

> Generated integer: `10` (random between 10-100).

### Idempotent:

```bash
terraform apply
```

```
No changes. Your infrastructure matches the configuration.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

---

## Step 12 — Change max → Forces Replacement

Change `max` from 100 to 90:

```bash
cat > main.tf << 'EOF'
resource "random_string" "datagen" {
  length = 10
}

resource "random_integer" "rint" {
  min = 10
  max = 90
}
EOF
```

```bash
terraform apply
```

```
  # random_integer.rint must be replaced
-/+ resource "random_integer" "rint" {
      ~ id     = "10" -> (known after apply)
      ~ max    = 100 -> 90 # forces replacement
      ~ result = 10 -> (known after apply)
        # (1 unchanged attribute hidden)
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

Type `yes`:

```
random_integer.rint: Destroying... [id=10]
random_integer.rint: Destruction complete after 0s
random_integer.rint: Creating...
random_integer.rint: Creation complete after 0s [id=58]

Apply complete! Resources: 1 added, 0 changed, 1 destroyed.
```

> New value: `58`. Changing `max` forced a replacement — same pattern as changing `length` on random_string.

---

## Step 13 — Clean Up

```bash
terraform destroy
```

Type `yes`:

```
random_integer.rint: Destroying... [id=58]
random_string.datagen: Destroying... [id=]bHhiY64qd]
random_integer.rint: Destruction complete after 0s
random_string.datagen: Destruction complete after 0s

Destroy complete! Resources: 2 destroyed.
```

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| `terraform validate` | Catches syntax errors before plan — fast, no API calls |
| `random_string` | Generates random text, stored in state |
| `random_integer` | Generates random number in a range |
| **State file** | JSON file storing resource attributes — Terraform's memory |
| `terraform state list` | See what Terraform tracks |
| `terraform state show` | See full details of one resource |
| **Idempotency** | Apply twice → same value (read from state) |
| `# forces replacement` | Changing length/min/max destroys + recreates |
| **Add resource** | Only the new one is created |
| **Remove resource** | Only the removed one is destroyed |
| `+` create / `-` destroy / `-/+` replace | Plan symbol meanings |

### terraform validate vs plan vs apply

```
validate  →  Checks syntax only (instant, offline)
plan      →  Checks syntax + compares state vs code (reads APIs)
apply     →  Executes the plan (creates/updates/destroys)

Always: validate → plan → apply
```

> **Next:** Proceed to **006** for more random resource types, resource chaining, keepers, and count/for_each.
