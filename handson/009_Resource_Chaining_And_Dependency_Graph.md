# 009 — Resource Chaining & Dependency Graph

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~10 minutes

---

## Concept

When one resource references another's attribute, Terraform **automatically detects the dependency** and creates them in the right order. You never need to specify "create A before B" — Terraform figures it out.

```
random_pet.server.id   ──┐
                         ├──►  local_file.config  (uses both values)
random_id.deploy.hex   ──┘

Terraform creates random_pet and random_id FIRST,
then local_file — because it references them.
```

---

## Prerequisites

Continue from 008 (same directory with random_pet, random_string, random_id):

```bash
cd ~/tf_works/003_random
```

---

## Step 1 — Chain random values into a local_file

Add to `main.tf`:

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

## Step 2 — Init (need local provider now) and apply

```bash
terraform init
terraform apply -auto-approve
```

```
local_file.server_config: Creating...
local_file.server_config: Creation complete after 0s [id=...]

Outputs:

config_file = "/tmp/keen-starling-config.txt"
deploy_hex  = "a1b7b474"
password    = <sensitive>
pet_name    = "keen-starling"
```

## Step 3 — Verify the chained file

```bash
cat "/tmp/keen-starling-config.txt"
```

```
  Server Name: keen-starling
  Deploy ID:   a1b7b474
  Generated password stored securely.
```

> **Resource chaining!** `local_file` used values from `random_pet` and `random_id`. Terraform created random resources FIRST, then the file. You didn't specify order.

---

## How Does Terraform Know the Order?

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

> Independent resources (like `random_string.password`) are created **in parallel** since nothing depends on them.

---

## Step 4 — Visualize the graph

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

> This is DOT format. With `graphviz`: `terraform graph | dot -Tpng > graph.png`

---

## Step 5 — What happens when a dependency changes?

Force a new pet name:

```bash
terraform apply -replace=random_pet.server -auto-approve
```

```
  # random_pet.server will be replaced
  # local_file.server_config must be replaced
    (because random_pet.server.id changed)
```

> Changing `random_pet.server` automatically triggers `local_file.server_config` to update — because it references the pet name in its filename and content. **Cascading updates through the dependency chain.**

---

## Step 6 — Explicit dependency with depends_on

Sometimes there's a hidden dependency that Terraform can't detect from references:

```bash
cat >> main.tf << 'EOF'

resource "random_pet" "backup" {
  length = 2

  # This resource has no reference to server_config,
  # but we want it created AFTER the config file
  depends_on = [local_file.server_config]
}

output "backup_name" {
  value = random_pet.backup.id
}
EOF
```

```bash
terraform apply -auto-approve
```

> `depends_on` forces ordering when there's no attribute reference. Use it sparingly — implicit dependencies (via references) are preferred.

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| Resource chaining | Reference another resource's attribute → auto-dependency |
| Dependency graph | Terraform builds a DAG from references |
| `terraform graph` | Visualize the DAG (DOT format) |
| Parallel execution | Independent resources are created simultaneously |
| Cascading updates | Changing a dependency triggers dependents to update |
| `depends_on` | Force ordering when there's no reference-based dependency |

> **Next:** Proceed to **010** for keepers — controlled recreation of random resources.
