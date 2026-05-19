# 012 — for_each: Creating Named Resources

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~10 minutes

---

## Concept

`for_each` creates resources keyed by **name** instead of index. This is more stable than `count` — removing one item only destroys that resource, others stay untouched.

```
count:       fleet[0], fleet[1], fleet[2]       ← index shifts on delete!
for_each:    pw["dev"], pw["staging"], pw["prod"] ← stable on delete ✅

Remove "staging":
  count:     [1] and [2] shift → BOTH recreated
  for_each:  only pw["staging"] destroyed → dev and prod SAFE
```

---

## Prerequisites

Create a fresh project:

```bash
mkdir -p ~/tf_works/012_foreach
cd ~/tf_works/012_foreach
```

```bash
cat > main.tf << 'EOF'
terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}
EOF

terraform init
```

---

## Step 1 — for_each with a map

```bash
cat >> main.tf << 'EOF'

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

## Step 2 — Apply

```bash
terraform apply -auto-approve
```

```
random_string.env_password["dev"]: Creating...
random_string.env_password["prod"]: Creating...
random_string.env_password["staging"]: Creating...

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

## Step 3 — Check state (keyed by name!)

```bash
terraform state list
```

```
random_string.env_password["dev"]
random_string.env_password["prod"]
random_string.env_password["staging"]
```

> Not `[0]`, `[1]`, `[2]` — keyed by `"dev"`, `"staging"`, `"prod"`.

## Step 4 — View the passwords

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

> Each got a different length as configured in the map.

---

## Step 5 — Remove "staging" — ONLY staging destroyed

Edit the variable — remove staging:

```bash
cat > main.tf << 'EOF'
terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

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

> **Only "staging" destroyed.** "dev" and "prod" passwords are untouched. This is the key advantage over count.

```bash
terraform apply -auto-approve
```

---

## Step 6 — Add a new environment

Add "qa":

```bash
cat > main.tf << 'EOF'
terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

variable "environments" {
  default = {
    dev  = 12
    qa   = 14
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
  # random_string.env_password["qa"] will be created
  + resource "random_string" "env_password" { ... }

Plan: 1 to add, 0 to change, 0 to destroy.
```

> Only "qa" created. "dev" and "prod" untouched. Adding and removing keys is safe.

```bash
terraform apply -auto-approve
```

---

## Step 7 — for_each with a set (list)

```bash
cat >> main.tf << 'EOF'

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

> With a `set(string)`, `each.key` and `each.value` are the same (the string itself).

---

## Step 8 — for_each to create local files per environment

```bash
cat >> main.tf << 'EOF'

resource "local_file" "env_config" {
  for_each = var.environments
  filename = "/tmp/${each.key}-config.txt"
  content  = "Environment: ${each.key}\nPassword length: ${each.value}"
}

output "config_files" {
  value = { for k, v in local_file.env_config : k => v.filename }
}
EOF
```

```bash
terraform apply -auto-approve
```

```
config_files = {
  "dev"  = "/tmp/dev-config.txt"
  "prod" = "/tmp/prod-config.txt"
  "qa"   = "/tmp/qa-config.txt"
}
```

```bash
cat /tmp/dev-config.txt
```

```
Environment: dev
Password length: 12
```

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
| `count` | Truly identical copies, conditional creation (`count = bool ? 1 : 0`) |
| `for_each` | Each resource has a name or identity (environments, users, regions) |

> **Default to `for_each`.** Only use `count` for simple "give me N of these" or conditional creation.

---

## Clean Up

```bash
terraform destroy -auto-approve
cd ~
rm -rf ~/tf_works/012_foreach
```

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| `for_each = map` | Create resources keyed by map keys |
| `each.key` | Current map key ("dev", "prod") |
| `each.value` | Current map value (12, 24) |
| `for_each = set` | Works with sets too (key = value) |
| Stable removal | Removing a key only destroys that resource |
| Safe addition | Adding a key only creates that resource |
| `{ for k, v in ... }` | Transform for_each results into output map |
| count vs for_each | for_each is stable, count shifts indices |

> **Next:** You've mastered Terraform fundamentals with local + random providers! Proceed to AWS setup to start deploying cloud resources.
