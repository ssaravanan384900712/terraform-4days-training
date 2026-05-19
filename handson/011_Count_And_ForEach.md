# 011 — count & for_each: Creating Multiple Resources

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~15 minutes

---

## Concept

So far each resource block creates ONE resource. But what if you need 3 servers, or a password per environment? Terraform gives you two ways:

```
count:      Create N identical copies, indexed [0], [1], [2]
for_each:   Create named copies from a map, keyed ["dev"], ["prod"]

┌────────────────────────────────────────────────────────┐
│                                                        │
│  count = 3                    for_each = { dev, prod } │
│                                                        │
│  fleet[0] = "light-fox"      pw["dev"]  = "aB3$kL"    │
│  fleet[1] = "bold-ram"       pw["prod"] = "xY9#mN"    │
│  fleet[2] = "calm-frog"                                │
│       │                           │                    │
│  Index-based (fragile)       Key-based (stable) ✅     │
│                                                        │
└────────────────────────────────────────────────────────┘
```

---

## Prerequisites

Continue from previous lab or create fresh:

```bash
mkdir -p ~/tf_works/011_count_foreach
cd ~/tf_works/011_count_foreach
```

```bash
cat > main.tf << 'EOF'
terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
EOF

terraform init
```

---

## Part 1 — count

### Step 1 — Create 3 random pets with count

```bash
cat >> main.tf << 'EOF'

resource "random_pet" "fleet" {
  count  = 3
  length = 2
}

output "fleet_names" {
  value = random_pet.fleet[*].id
}
EOF
```

### Step 2 — Apply

```bash
terraform apply -auto-approve
```

```
random_pet.fleet[0]: Creating...
random_pet.fleet[1]: Creating...
random_pet.fleet[2]: Creating...
random_pet.fleet[0]: Creation complete after 0s [id=light-fox]
random_pet.fleet[1]: Creation complete after 0s [id=bold-ram]
random_pet.fleet[2]: Creation complete after 0s [id=calm-frog]

fleet_names = [
  "light-fox",
  "bold-ram",
  "calm-frog",
]
```

### Understanding count

```
resource "random_pet" "fleet" {
  count = 3        ← Creates 3 instances
}

random_pet.fleet[0]  →  "light-fox"
random_pet.fleet[1]  →  "bold-ram"
random_pet.fleet[2]  →  "calm-frog"
```

### Step 3 — The splat expression [*]

```
random_pet.fleet[*].id

The [*] "splat" collects an attribute from ALL instances into a list:
→  ["light-fox", "bold-ram", "calm-frog"]
```

### Step 4 — Check state

```bash
terraform state list
```

```
random_pet.fleet[0]
random_pet.fleet[1]
random_pet.fleet[2]
```

### Step 5 — Using count.index

```bash
cat > local_demo.tf << 'EOF'
resource "local_file" "numbered" {
  count    = 3
  filename = "/tmp/file-${count.index}.txt"
  content  = "This is file number ${count.index + 1} of 3"
}

output "file_paths" {
  value = local_file.numbered[*].filename
}
EOF
```

```bash
terraform init
terraform apply -auto-approve
```

```
file_paths = [
  "/tmp/file-0.txt",
  "/tmp/file-1.txt",
  "/tmp/file-2.txt",
]
```

```bash
cat /tmp/file-0.txt
```

```
This is file number 1 of 3
```

> `count.index` starts at 0. Use `count.index + 1` for human-friendly numbering.

### Step 6 — The count GOTCHA

Change count from 3 to 2:

```bash
sed -i 's/count    = 3/count    = 2/' local_demo.tf
terraform plan
```

```
  # local_file.numbered[2] will be destroyed
  # (because local_file.numbered[2] is not in configuration)

Plan: 0 to add, 0 to change, 1 to destroy.
```

> Only `[2]` is removed. That's fine. But what if you removed `[0]` from the middle? Items `[1]` and `[2]` would shift to `[0]` and `[1]` — causing unnecessary recreation. **This is why for_each is preferred.**

```bash
# Revert
sed -i 's/count    = 2/count    = 3/' local_demo.tf
terraform apply -auto-approve
```

---

## Part 2 — for_each

### Step 7 — Create per-environment passwords

```bash
cat > foreach_demo.tf << 'EOF'
variable "environments" {
  default = {
    dev     = 12
    staging = 16
    prod    = 24
  }
}

resource "random_string" "env_password" {
  for_each = var.environments
  length   = each.value
  special  = true
}

output "env_passwords" {
  value     = { for k, v in random_string.env_password : k => v.result }
  sensitive = true
}
EOF
```

### How for_each works

```
for_each = var.environments
           │
           └── Iterates over the map:
               "dev"     = 12
               "staging" = 16
               "prod"    = 24

each.key   → "dev", "staging", "prod"     (the map key)
each.value → 12, 16, 24                   (the map value)
```

### Step 8 — Apply

```bash
terraform apply -auto-approve
```

```
random_string.env_password["dev"]: Creating...
random_string.env_password["prod"]: Creating...
random_string.env_password["staging"]: Creating...

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

### Step 9 — Check state

```bash
terraform state list | grep env_password
```

```
random_string.env_password["dev"]
random_string.env_password["prod"]
random_string.env_password["staging"]
```

> Keyed by name! Not `[0]`, `[1]`, `[2]`.

### Step 10 — View the passwords

```bash
terraform output -json env_passwords | python3 -m json.tool
```

```json
{
    "dev": "aB3$kL9m!Qx2",
    "prod": "xY9#mN2$pQ4!wR7@hJ5*kL8&",
    "staging": "fG6!hJ3@kL9$mN2*"
}
```

> Each environment got a different length password as configured.

### Step 11 — Remove "staging" — ONLY staging is destroyed

Edit `foreach_demo.tf` — remove staging from the map:

```bash
cat > foreach_demo.tf << 'EOF'
variable "environments" {
  default = {
    dev  = 12
    prod = 24
  }
}

resource "random_string" "env_password" {
  for_each = var.environments
  length   = each.value
  special  = true
}

output "env_passwords" {
  value     = { for k, v in random_string.env_password : k => v.result }
  sensitive = true
}
EOF
```

```bash
terraform plan
```

```
  # random_string.env_password["staging"] will be destroyed
  # (because key "staging" is not in for_each map)

Plan: 0 to add, 0 to change, 1 to destroy.
```

> **Only "staging" is destroyed.** "dev" and "prod" are untouched. This is why for_each is better than count — stable on removal.

```bash
terraform apply -auto-approve
```

---

## Part 3 — for_each with a set (list)

```bash
cat > set_demo.tf << 'EOF'
variable "users" {
  type    = set(string)
  default = ["alice", "bob", "charlie"]
}

resource "random_string" "user_token" {
  for_each = var.users
  length   = 32
  special  = false
}

output "user_tokens" {
  value     = { for k, v in random_string.user_token : k => v.result }
  sensitive = true
}
EOF
```

```bash
terraform apply -auto-approve
```

```bash
terraform state list | grep user_token
```

```
random_string.user_token["alice"]
random_string.user_token["bob"]
random_string.user_token["charlie"]
```

> `for_each` works with both `map` and `set(string)`. With a set, `each.key` and `each.value` are the same (the string itself).

---

## count vs for_each — When to Use Which

```
count:                           for_each:
  fleet[0] = "light-fox"          pw["dev"]     = "aB3..."
  fleet[1] = "bold-ram"           pw["staging"] = "fG6..."
  fleet[2] = "calm-frog"          pw["prod"]    = "xY9..."
       │                                  │
  Index-based (fragile)          Key-based (stable) ✅
  Remove [0] → [1],[2] shift!    Remove "staging" → others safe!
```

| Use | When |
|-----|------|
| `count` | Truly identical copies with no meaningful name (e.g., 3 identical workers) |
| `for_each` | Each resource has a name or identity (environments, users, regions) |

> **Default to `for_each`.** Only use `count` for simple "give me N of these" situations.

---

## Clean Up

```bash
terraform destroy -auto-approve
cd ~
rm -rf ~/tf_works/011_count_foreach
```

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| `count = N` | Create N identical resources |
| `count.index` | Current index (0, 1, 2...) |
| `[*]` splat | Collect attribute from all count instances |
| Count gotcha | Removing item shifts indices — causes recreation |
| `for_each = map` | Create named resources from key-value pairs |
| `each.key` / `each.value` | Access current map entry |
| `for_each = set` | Works with sets too (key = value) |
| for_each stability | Removing a key only destroys that resource |
| Rule of thumb | Default to `for_each`, use `count` for identical copies |

> **Next:** You've mastered Terraform fundamentals! Proceed to AWS setup to start deploying cloud resources.
