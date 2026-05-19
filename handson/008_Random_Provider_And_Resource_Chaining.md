# 008 — Random Resource Types: pet, string, id

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~15 minutes

---

## Concept

The `random` provider has several resource types for generating different kinds of random values. All persist in state — apply twice, same value. This lab covers the three most common ones.

```
random_pet      →  "keen-starling"      (human-readable names)
random_string   →  "aB3$kL9m!Qx2Fp7z"  (passwords, tokens)
random_id       →  "a1b7b474"           (unique hex IDs for naming)
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

## Summary

| Concept | What You Learned |
|---------|-----------------|
| `random_pet` | Human-readable random names |
| `random_string` | Random passwords with `sensitive` |
| `random_id` | Unique hex/decimal IDs |
| Idempotency | Apply twice → same random value (stored in state) |
| `-replace` | Force recreation of a specific resource |

> **Next:** Proceed to **009** for resource chaining, keepers, count, and for_each.
