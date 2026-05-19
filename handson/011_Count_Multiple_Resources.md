# 011 — count: Creating Multiple Resources

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~10 minutes

---

## Concept

So far each resource block creates ONE resource. What if you need 3 servers? `count` lets you create N identical copies from a single block.

```
resource "random_pet" "fleet" {
  count = 3
}

Result:
  fleet[0] = "light-fox"
  fleet[1] = "bold-ram"
  fleet[2] = "calm-frog"
       │
       └── Index-based: [0], [1], [2]
```

---

## Prerequisites

Create a fresh project:

```bash
mkdir -p ~/tf_works/011_count
cd ~/tf_works/011_count
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

## Step 1 — Create 3 random pets with count

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

## Step 2 — Apply

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

---

## Step 3 — The splat expression [*]

```
random_pet.fleet[*].id

The [*] "splat" collects an attribute from ALL instances into a list:
→  ["light-fox", "bold-ram", "calm-frog"]
```

## Step 4 — Check state

```bash
terraform state list
```

```
random_pet.fleet[0]
random_pet.fleet[1]
random_pet.fleet[2]
```

---

## Step 5 — Using count.index

```bash
cat >> main.tf << 'EOF'

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

---

## Step 6 — count with a variable

```bash
cat >> main.tf << 'EOF'

variable "server_count" {
  description = "How many servers to create"
  type        = number
  default     = 3
}

resource "random_pet" "servers" {
  count  = var.server_count
  length = 2
}

output "server_names" {
  value = random_pet.servers[*].id
}
EOF
```

```bash
terraform apply -auto-approve
```

```
server_names = [
  "happy-panda",
  "calm-eagle",
  "bold-fox",
]
```

Change the count:

```bash
terraform apply -auto-approve -var='server_count=5'
```

```
  # random_pet.servers[3] will be created
  # random_pet.servers[4] will be created

Plan: 2 to add, 0 to change, 0 to destroy.
```

> Only 2 new resources created. Existing [0], [1], [2] untouched.

---

## Step 7 — The count GOTCHA (index shift)

Reduce back to 2:

```bash
terraform apply -auto-approve -var='server_count=2'
```

```
  # random_pet.servers[2] will be destroyed
  # random_pet.servers[3] will be destroyed
  # random_pet.servers[4] will be destroyed

Plan: 0 to add, 0 to change, 3 to destroy.
```

> Removing from the end is fine — [2], [3], [4] are destroyed, [0] and [1] untouched.

**But what if you need to remove a SPECIFIC item from the middle?** With count, you can't. Removing item [0] shifts [1]→[0] and [2]→[1], causing unnecessary destruction and recreation.

```
Before:   fleet[0]="fox"  fleet[1]="ram"  fleet[2]="frog"
Remove [0] with count:
After:    fleet[0]="ram"  fleet[1]="frog"
          ↑ was [1]       ↑ was [2]
          Both RECREATED because indices shifted!
```

> **This is why `for_each` is preferred** — it uses keys, not indices. Coming in the next lab.

---

## Step 8 — Conditional creation with count

```bash
cat >> main.tf << 'EOF'

variable "create_backup" {
  type    = bool
  default = true
}

resource "random_pet" "backup" {
  count  = var.create_backup ? 1 : 0
  length = 3
}

output "backup_name" {
  value = var.create_backup ? random_pet.backup[0].id : "none"
}
EOF
```

```bash
terraform apply -auto-approve
```

```
backup_name = "brave-calm-fox"
```

```bash
terraform apply -auto-approve -var='create_backup=false'
```

```
  # random_pet.backup[0] will be destroyed

backup_name = "none"
```

> `count = condition ? 1 : 0` is a common pattern to conditionally create a resource. `1` = exists, `0` = doesn't exist.

---

## Clean Up

```bash
terraform destroy -auto-approve
cd ~
rm -rf ~/tf_works/011_count
```

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| `count = N` | Create N identical resources |
| `count.index` | Current index (0, 1, 2...) |
| `[*]` splat | Collect attribute from all instances into a list |
| `count = var.N` | Dynamic count from a variable |
| `count = bool ? 1 : 0` | Conditional resource creation |
| Index shift gotcha | Removing from middle recreates shifted resources |
| When to use count | Truly identical copies, conditional creation |

> **Next:** Proceed to **012** for `for_each` — the preferred way to create named resources.
