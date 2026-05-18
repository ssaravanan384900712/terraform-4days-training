# 004 — Random Provider & Resource Chaining

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~25 minutes

---

## Concept

The `random` provider generates random values that **persist in state**. Once created, they don't change — unless you tell them to. This teaches two critical concepts before AWS:

1. **Idempotency** — apply twice, same random value (it's in state)
2. **Resource chaining** — one resource's output feeds into another's input

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ random_pet   │────►│ local_file   │────►│ output       │
│ "server"     │     │ uses pet     │     │ shows result │
│              │     │ name in      │     │              │
│ generates:   │     │ filename &   │     │              │
│ "bold-fox"   │     │ content      │     │              │
└──────────────┘     └──────────────┘     └──────────────┘
     Terraform auto-detects this dependency!
```

---

## Part 1 — Setup

### Step 1 — Create project

```bash
mkdir -p ~/tf_works/003_random
cd ~/tf_works/003_random
```

---

## Part 2 — random_pet (Your First Random Resource)

### Step 2 — Create main.tf

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

resource "random_pet" "server" {
  length = 2
}

output "pet_name" {
  value = random_pet.server.id
}
EOF
```

### Step 3 — Init and apply

```bash
terraform init
terraform apply -auto-approve
```

```
random_pet.server: Creating...
random_pet.server: Creation complete after 0s [id=prime-piglet]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

pet_name = "prime-piglet"
```

> Your name will be different — it's random!

### Step 4 — Apply again — IDEMPOTENCY

```bash
terraform apply -auto-approve
```

```
random_pet.server: Refreshing state... [id=prime-piglet]

No changes. Your infrastructure matches the configuration.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

pet_name = "prime-piglet"
```

> **Same name!** The random value is stored in state. Terraform doesn't regenerate it. This is idempotency — the core principle of IaC. Apply 100 times, same result.

### Step 5 — Force a new name with taint/replace

```bash
terraform apply -replace=random_pet.server -auto-approve
```

```
random_pet.server: Destroying... [id=prime-piglet]
random_pet.server: Destruction complete after 0s
random_pet.server: Creating...
random_pet.server: Creation complete after 0s [id=keen-starling]

Apply complete! Resources: 1 added, 0 changed, 1 destroyed.

Outputs:

pet_name = "keen-starling"
```

> `-replace` forces Terraform to destroy and recreate. New random name generated.

---

## Part 3 — random_string (Passwords)

### Step 6 — Add a random password

Add to `main.tf`:

```bash
cat >> main.tf << 'EOF'

resource "random_string" "password" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
}

output "password" {
  value     = random_string.password.result
  sensitive = true
}
EOF
```

### Step 7 — Apply

```bash
terraform apply -auto-approve
```

```
random_string.password: Creating...
random_string.password: Creation complete after 0s [id=aB3$kL9m!Qx2Fp7z]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

password = <sensitive>
pet_name = "keen-starling"
```

> Password is hidden! `sensitive = true` on the output keeps it out of terminal display.

### Step 8 — Retrieve the sensitive value

```bash
terraform output -raw password
```

```
aB3$kL9m!Qx2Fp7z
```

> `-raw` gets the actual value. `-json` also works. Only the default display hides it.

---

## Part 4 — random_id (Unique Identifiers)

### Step 9 — Add random_id

Add to `main.tf`:

```bash
cat >> main.tf << 'EOF'

resource "random_id" "deploy" {
  byte_length = 4
}

output "deploy_hex" {
  value = random_id.deploy.hex
}

output "deploy_dec" {
  value = random_id.deploy.dec
}
EOF
```

### Step 10 — Apply

```bash
terraform apply -auto-approve
```

```
random_id.deploy: Creating...
random_id.deploy: Creation complete after 0s [id=obc0dA]

Outputs:

deploy_dec = "2814632052"
deploy_hex = "a1b7b474"
password   = <sensitive>
pet_name   = "keen-starling"
```

> `random_id` gives you hex and decimal representations. Great for unique resource names like S3 bucket suffixes.

---

## Part 5 — Resource Chaining (The Key Concept)

### Step 11 — Chain random values into a local_file

Add the local provider and a chained resource to `main.tf`:

```bash
cat >> main.tf << 'EOF'

resource "local_file" "server_config" {
  filename = "/tmp/${random_pet.server.id}-config.txt"
  content  = <<-EOT
    Server Name: ${random_pet.server.id}
    Deploy ID:   ${random_id.deploy.hex}
    Generated password stored securely.
  EOT
}

output "config_file" {
  value = local_file.server_config.filename
}
EOF
```

### Step 12 — Init (need local provider now) and apply

```bash
terraform init    # Downloads local provider
terraform apply -auto-approve
```

```
local_file.server_config: Creating...
local_file.server_config: Creation complete after 0s [id=...]

Outputs:

config_file = "/tmp/keen-starling-config.txt"
deploy_dec  = "2814632052"
deploy_hex  = "a1b7b474"
password    = <sensitive>
pet_name    = "keen-starling"
```

### Step 13 — Verify

```bash
cat "/tmp/keen-starling-config.txt"
```

```
  Server Name: keen-starling
  Deploy ID:   a1b7b474
  Generated password stored securely.
```

> **Resource chaining!** `local_file` used values from `random_pet` and `random_id`. Terraform automatically knew to create the random resources FIRST, then the file. You didn't need to specify order.

### How does Terraform know the order?

```
random_pet.server.id   ←── referenced in local_file filename + content
random_id.deploy.hex   ←── referenced in local_file content
                 │
                 ▼
Terraform builds a DEPENDENCY GRAPH:
  random_pet.server    ─┐
  random_id.deploy     ─┼──► local_file.server_config
  random_string.password (independent — no one references it)
```

### Step 14 — Visualize the graph

```bash
terraform graph
```

```
digraph {
  ...
  "random_pet.server" -> "local_file.server_config"
  "random_id.deploy" -> "local_file.server_config"
  ...
}
```

> This is a DOT-format graph. If you have `graphviz` installed: `terraform graph | dot -Tpng > graph.png`

---

## Part 6 — Keepers (Controlled Recreation)

### Step 15 — Add keepers to random_pet

Keepers are a map — when any keeper value changes, the random resource is **destroyed and recreated**.

Create a new file `keepers.tf`:

```bash
cat > keepers.tf << 'EOF'
variable "app_version" {
  description = "Application version — changing this regenerates names"
  type        = string
  default     = "1.0.0"
}

resource "random_pet" "app" {
  keepers = {
    version = var.app_version
  }
  length = 2
}

output "app_name" {
  value = "app-${random_pet.app.id}-v${var.app_version}"
}
EOF
```

### Step 16 — Apply

```bash
terraform apply -auto-approve
```

```
random_pet.app: Creating...
random_pet.app: Creation complete after 0s [id=sunny-cobra]

app_name = "app-sunny-cobra-v1.0.0"
```

### Step 17 — Apply again — no change

```bash
terraform apply -auto-approve
```

```
No changes. Your infrastructure matches the configuration.
```

> Same keeper value → same pet name. Idempotent.

### Step 18 — Change the version → forces new name

```bash
terraform apply -auto-approve -var='app_version=2.0.0'
```

```
  # random_pet.app must be replaced
-/+ resource "random_pet" "app" {
      ~ id       = "sunny-cobra" -> (known after apply)
      ~ keepers  = {
          ~ "version" = "1.0.0" -> "2.0.0"    # forces replacement
        }
    }

random_pet.app: Destroying... [id=sunny-cobra]
random_pet.app: Destruction complete after 0s
random_pet.app: Creating...
random_pet.app: Creation complete after 0s [id=noble-whale]

app_name = "app-noble-whale-v2.0.0"
```

> **Keepers changed → resource replaced.** This is exactly how AWS AMI updates work later — change the AMI ID → EC2 instance gets replaced.

---

## Part 7 — count (Multiple Identical Resources)

### Step 19 — Create multiple random pets with count

Create `count_demo.tf`:

```bash
cat > count_demo.tf << 'EOF'
resource "random_pet" "fleet" {
  count  = 3
  length = 2
}

output "fleet_names" {
  value = random_pet.fleet[*].id
}
EOF
```

### Step 20 — Apply

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

### Understanding count and splat

```
random_pet.fleet[0]   →  "light-fox"
random_pet.fleet[1]   →  "bold-ram"
random_pet.fleet[2]   →  "calm-frog"

random_pet.fleet[*].id  →  ["light-fox", "bold-ram", "calm-frog"]
                   │
                   └── [*] is the "splat" expression — collects all into a list
```

### Step 21 — Check state

```bash
terraform state list | grep fleet
```

```
random_pet.fleet[0]
random_pet.fleet[1]
random_pet.fleet[2]
```

> ⚠️ **count gotcha:** If you remove item `[0]`, items `[1]` and `[2]` shift down to `[0]` and `[1]` — causing unnecessary recreation. This is why `for_each` is preferred for most cases.

---

## Part 8 — for_each (Named Resources)

### Step 22 — Create per-environment passwords

Create `foreach_demo.tf`:

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

### Step 23 — Apply

```bash
terraform apply -auto-approve
```

```
random_string.env_password["dev"]: Creating...
random_string.env_password["prod"]: Creating...
random_string.env_password["staging"]: Creating...
...

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

### Step 24 — Check state

```bash
terraform state list | grep env_password
```

```
random_string.env_password["dev"]
random_string.env_password["prod"]
random_string.env_password["staging"]
```

> Keyed by name, not index! Removing "staging" only destroys that one. Others untouched.

### Step 25 — View the passwords

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

> Each environment got a different password length as configured in the map.

### count vs for_each

```
count:                           for_each:
  fleet[0] = "light-fox"          env_password["dev"] = "aB3..."
  fleet[1] = "bold-ram"           env_password["staging"] = "fG6..."
  fleet[2] = "calm-frog"          env_password["prod"] = "xY9..."
       │                                  │
       └── Index-based (fragile)          └── Key-based (stable)

Remove item [0] → [1] and [2] shift!   Remove "staging" → others unchanged!
```

> **Rule:** Use `for_each` when each resource has a meaningful name. Use `count` only for truly identical copies.

---

## Part 9 — Clean Up

```bash
terraform destroy -auto-approve
```

```
Destroy complete! Resources: X destroyed.
```

```bash
cd ~
rm -rf ~/tf_works/003_random
```

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| `random_pet` | Human-readable random names |
| `random_string` | Random passwords with `sensitive` |
| `random_id` | Unique hex/decimal IDs |
| Idempotency | Apply twice → same random value (stored in state) |
| `-replace` | Force recreation of a specific resource |
| Resource chaining | One resource uses another's output automatically |
| Dependency graph | Terraform determines order from references |
| `terraform graph` | Visualize dependencies |
| Keepers | Change a keeper → forces resource recreation |
| `count` | Create N identical resources (index-based) |
| `for_each` | Create named resources from a map (key-based, preferred) |
| `[*]` splat | Collect all count instances into a list |
| count vs for_each | for_each is stable on removal, count shifts |

> **Next:** Proceed to **004** or the AWS setup lab to start deploying cloud resources!
