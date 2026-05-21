# 036 — Terraform Workspaces

**By: Saravanan Sundaramoorthy**
**Environment:** Local (no cloud credentials needed)
**Time to complete:** ~10 minutes

---

## Topic

| Concept | What it means |
|---------|--------------|
| **Workspace** | An isolated state file within a single Terraform configuration directory |
| **`default` workspace** | Always exists; created automatically; cannot be deleted |
| **`terraform.workspace`** | Built-in string variable that contains the current workspace name |
| **`.terraform/environment`** | File that records which workspace is currently selected |
| **`terraform.tfstate.d/`** | Directory containing state files for all non-default workspaces |
| **State isolation** | Each workspace has its own `terraform.tfstate` — resources in one workspace are invisible to another |

Workspaces let a single Terraform configuration manage multiple isolated sets of resources. Instead of duplicating your `.tf` files into `dev/`, `staging/`, and `prod/` directories, you keep one set of files and switch between workspaces. Terraform maintains a separate state file for each workspace.

---

## The State File Locations

```
~/terraform-workspaces-036/
├── terraform.tfstate              ← state for the "default" workspace
└── terraform.tfstate.d/
    ├── dev/
    │   └── terraform.tfstate      ← state for the "dev" workspace
    ├── staging/
    │   └── terraform.tfstate      ← state for the "staging" workspace
    └── prod/
        └── terraform.tfstate      ← state for the "prod" workspace
```

The `default` workspace state file is always at the root level. Every other workspace gets its own subdirectory under `terraform.tfstate.d/`.

---

## What We Will Build

A single configuration that writes environment-specific config files to `/tmp/`:

| Workspace | Output file |
|-----------|-------------|
| `default` | `/tmp/robochef-default-config.txt` |
| `dev` | `/tmp/robochef-dev-config.txt` |
| `staging` | `/tmp/robochef-staging-config.txt` |
| `prod` | `/tmp/robochef-prod-config.txt` |

Each file contains its workspace name, site name, tier label, and a random ID unique to that workspace. The random ID does not change between applies within the same workspace — proving state isolation.

---

## Directory Layout

```
~/terraform-workspaces-036/
├── providers.tf
├── main.tf
└── outputs.tf
```

---

## Step 1 — Create the Project Directory

```bash
mkdir ~/terraform-workspaces-036
cd ~/terraform-workspaces-036
```

---

## Step 2 — providers.tf

```hcl
# providers.tf
terraform {
  required_version = ">= 1.0"

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

# No credentials needed — random and local providers are fully offline.
```

---

## Step 3 — main.tf

```hcl
# main.tf

# ------------------------------------------------------------------
# random_string — generates a unique ID per workspace.
# Because each workspace has its own state, this resource creates
# a NEW random string when you first apply in each workspace, then
# keeps the same string on subsequent applies in that workspace.
# ------------------------------------------------------------------
resource "random_string" "env_id" {
  length  = 8
  upper   = false
  special = false
}

# ------------------------------------------------------------------
# locals — workspace-aware configuration map
#
# terraform.workspace is a built-in variable that holds the name of
# the currently selected workspace ("default", "dev", "staging", etc.)
#
# We use lookup() with a default so that any unrecognized workspace
# name falls back to the "default" config rather than erroring.
# ------------------------------------------------------------------
locals {
  env_config = {
    default = { site = "robochef.co", tier = "dev",     note = "default workspace — treat as dev" }
    dev     = { site = "robochef.co", tier = "dev",     note = "development environment" }
    staging = { site = "robochef.co", tier = "staging", note = "pre-production staging environment" }
    prod    = { site = "robochef.co", tier = "prod",    note = "production — handle with care" }
  }

  # lookup() returns env_config[terraform.workspace] if it exists,
  # otherwise returns env_config["default"] as the fallback.
  config = lookup(local.env_config, terraform.workspace, local.env_config["default"])
}

# ------------------------------------------------------------------
# local_file — writes an environment-specific config file.
#
# The filename includes terraform.workspace so each workspace writes
# to a different path — making it easy to verify isolation.
# ------------------------------------------------------------------
resource "local_file" "env_config" {
  filename        = "/tmp/robochef-${terraform.workspace}-config.txt"
  file_permission = "0644"
  content         = <<-EOT
    Workspace : ${terraform.workspace}
    Site      : ${local.config.site}
    Tier      : ${local.config.tier}
    Note      : ${local.config.note}
    Unique ID : ${random_string.env_id.result}
    Written   : ${timestamp()}
  EOT
}
```

---

## Step 4 — outputs.tf

```hcl
# outputs.tf

output "workspace" {
  description = "The currently selected workspace"
  value       = terraform.workspace
}

output "config_file" {
  description = "Path to the config file written for this workspace"
  value       = local_file.env_config.filename
}

output "env_id" {
  description = "The random ID unique to this workspace"
  value       = random_string.env_id.result
}

output "tier" {
  description = "The tier label for this workspace"
  value       = local.config.tier
}
```

---

## Step 5 — Init

```bash
cd ~/terraform-workspaces-036
terraform init
```

Expected output:

```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/random versions matching "~> 3.0"...
- Finding hashicorp/local versions matching "~> 2.0"...
- Installing hashicorp/random v3.6.3...
- Installing hashicorp/local v2.5.2...
Terraform has been successfully initialized!
```

---

## Step 6 — Check the Current Workspace

Before creating any workspaces, confirm you are in the default workspace:

```bash
terraform workspace show
```

Output:

```
default
```

```bash
terraform workspace list
```

Output:

```
* default
```

The asterisk (`*`) marks the currently selected workspace. Right now only `default` exists.

Check the internal tracking file:

```bash
cat .terraform/environment
```

Output:

```
default
```

Terraform writes the selected workspace name to this file. If the file says `default`, you are in the default workspace.

---

## Step 7 — Apply in the Default Workspace

```bash
terraform apply -auto-approve
```

Expected output:

```
random_string.env_id: Creating...
random_string.env_id: Creation complete after 0s [id=k7mxqwbn]
local_file.env_config: Creating...
local_file.env_config: Creation complete after 0s [id=...]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:
config_file = "/tmp/robochef-default-config.txt"
env_id      = "k7mxqwbn"
tier        = "dev"
workspace   = "default"
```

Read the written file:

```bash
cat /tmp/robochef-default-config.txt
```

Output:

```
Workspace : default
Site      : robochef.co
Tier      : dev
Note      : default workspace — treat as dev
Unique ID : k7mxqwbn
Written   : 2026-05-21T10:00:00Z
```

State file location — the default workspace uses the root-level state file:

```bash
ls -lh terraform.tfstate
```

No `terraform.tfstate.d/` directory yet — it is only created when a non-default workspace is used.

---

## Step 8 — Create the dev Workspace

```bash
terraform workspace new dev
```

Output:

```
Created and switched to workspace "dev"!

You're now on a new, empty workspace. Terraform will act as if you are
starting with a completely clean slate, from an initial empty state.
```

Confirm:

```bash
terraform workspace show     # dev
cat .terraform/environment   # dev
```

The `.terraform/environment` file now says `dev`. Terraform will read and write state from `terraform.tfstate.d/dev/terraform.tfstate` for all future commands until you switch workspaces.

List workspaces:

```bash
terraform workspace list
```

Output:

```
* dev
  default
```

The asterisk is now on `dev`.

---

## Step 9 — Apply in dev

```bash
terraform apply -auto-approve
```

Expected output:

```
random_string.env_id: Creating...
random_string.env_id: Creation complete after 0s [id=p3nrtzam]
local_file.env_config: Creating...
local_file.env_config: Creation complete after 0s [id=...]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:
config_file = "/tmp/robochef-dev-config.txt"
env_id      = "p3nrtzam"
tier        = "dev"
workspace   = "dev"
```

Notice:
- The random ID is `p3nrtzam` — different from the default workspace's `k7mxqwbn`.
- The output file is `/tmp/robochef-dev-config.txt` — a different path from the default workspace.
- Both config files exist simultaneously on disk.

Read the dev config file:

```bash
cat /tmp/robochef-dev-config.txt
```

```
Workspace : dev
Site      : robochef.co
Tier      : dev
Note      : development environment
Unique ID : p3nrtzam
Written   : 2026-05-21T10:01:00Z
```

Check the state directory structure:

```bash
ls -lh terraform.tfstate.d/
ls -lh terraform.tfstate.d/dev/
```

Output:

```
drwxr-xr-x dev/

terraform.tfstate.d/dev/
-rw-r--r-- terraform.tfstate
```

The `dev` workspace state file is separate from the `default` state. The two workspaces do not share resources.

---

## Step 10 — Create the staging Workspace and Apply

```bash
terraform workspace new staging
terraform apply -auto-approve
```

Expected output:

```
Outputs:
config_file = "/tmp/robochef-staging-config.txt"
env_id      = "w9cklmds"
tier        = "staging"
workspace   = "staging"
```

```bash
cat /tmp/robochef-staging-config.txt
```

```
Workspace : staging
Site      : robochef.co
Tier      : staging
Note      : pre-production staging environment
Unique ID : w9cklmds
Written   : 2026-05-21T10:02:00Z
```

---

## Step 11 — Create the prod Workspace and Apply

```bash
terraform workspace new prod
terraform apply -auto-approve
```

Expected output:

```
Outputs:
config_file = "/tmp/robochef-prod-config.txt"
env_id      = "x1fbvyqr"
tier        = "prod"
workspace   = "prod"
```

```bash
cat /tmp/robochef-prod-config.txt
```

```
Workspace : prod
Site      : robochef.co
Tier      : prod
Note      : production — handle with care
Unique ID : x1fbvyqr
Written   : 2026-05-21T10:03:00Z
```

---

## Step 12 — List All Workspaces

```bash
terraform workspace list
```

Output:

```
  default
  dev
  staging
* prod
```

Four workspaces exist. The asterisk shows `prod` is currently selected.

---

## Step 13 — Inspect the State Directory

```bash
ls -lhR terraform.tfstate.d/
```

Output:

```
terraform.tfstate.d/:
drwxr-xr-x dev/
drwxr-xr-x staging/
drwxr-xr-x prod/

terraform.tfstate.d/dev/:
-rw-r--r-- terraform.tfstate

terraform.tfstate.d/staging/:
-rw-r--r-- terraform.tfstate

terraform.tfstate.d/prod/:
-rw-r--r-- terraform.tfstate
```

And the default workspace:

```bash
ls -lh terraform.tfstate
```

```
-rw-r--r-- terraform.tfstate    ← default workspace state, at the root level
```

Each workspace has its own independent state. The resources in `prod` are invisible to `dev`, and vice versa.

---

## Step 14 — Switch Between Workspaces and Read State

Switch to `dev` and read its output:

```bash
terraform workspace select dev
terraform output
```

Output:

```
config_file = "/tmp/robochef-dev-config.txt"
env_id      = "p3nrtzam"
tier        = "dev"
workspace   = "dev"
```

Switch to `default` and read its output:

```bash
terraform workspace select default
terraform output
```

Output:

```
config_file = "/tmp/robochef-default-config.txt"
env_id      = "k7mxqwbn"
tier        = "dev"
workspace   = "default"
```

The random IDs are different for each workspace. `terraform state list` only shows resources in the currently selected workspace:

```bash
terraform workspace select dev
terraform state list
```

Output:

```
local_file.env_config
random_string.env_id
```

Only the `dev` workspace resources appear. The `prod` resources do not show up here, even though they exist in their own state file.

---

## Step 15 — Apply Again in dev (Prove State Stability)

Switch to `dev` and apply again to confirm the random ID does not change:

```bash
terraform workspace select dev
terraform apply -auto-approve
```

Expected output:

```
local_file.env_config: Modifying... [content changed — timestamp updated]
local_file.env_config: Modifications complete after 0s

Apply complete! Resources: 0 added, 1 changed, 0 destroyed.

Outputs:
env_id = "p3nrtzam"   ← same ID as before
```

The `random_string.env_id` resource was NOT re-created — it is already in the `dev` state file with value `p3nrtzam`. Terraform reads from state and keeps it stable. This is state isolation at work.

---

## Step 16 — Show Current Workspace with terraform workspace show

```bash
terraform workspace show
```

Output:

```
dev
```

A simple one-liner to print the active workspace — useful in scripts:

```bash
# Use workspace name in a shell script
WORKSPACE=$(terraform workspace show)
echo "Currently in workspace: $WORKSPACE"
```

---

## Step 17 — Destroy Each Workspace

You must destroy each workspace from within that workspace. You cannot delete a workspace that has resources in state.

**Destroy dev:**

```bash
terraform workspace select dev
terraform destroy -auto-approve
rm -rf .terraform
```

```
random_string.env_id: Destroying...
local_file.env_config: Destroying...
Destroy complete! Resources: 2 destroyed.
```

**Destroy staging:**

```bash
terraform workspace select staging
terraform destroy -auto-approve
```

**Destroy prod:**

```bash
terraform workspace select prod
terraform destroy -auto-approve
```

**Destroy default:**

```bash
terraform workspace select default
terraform destroy -auto-approve
```

---

## Step 18 — Delete the Non-Default Workspaces

After destroying all resources in a workspace, you can delete the workspace itself. Note: the `default` workspace cannot be deleted.

```bash
# Must be in a different workspace to delete one
terraform workspace select default

terraform workspace delete dev
terraform workspace delete staging
terraform workspace delete prod
```

Expected output for each:

```
Deleted workspace "dev"!
```

Confirm:

```bash
terraform workspace list
```

Output:

```
* default
```

Only `default` remains. Its state is empty (you just destroyed everything).

Check the directory:

```bash
ls terraform.tfstate.d/    # should be empty or the directory may not exist
```

---

## Step 19 — Clean Up

```bash
rm -rf ~/terraform-workspaces-036/.terraform
rm -f  ~/terraform-workspaces-036/terraform.tfstate
rm -f  /tmp/robochef-default-config.txt \
       /tmp/robochef-dev-config.txt \
       /tmp/robochef-staging-config.txt \
       /tmp/robochef-prod-config.txt
```

---

## Workspace Commands Reference

| Command | What it does |
|---------|-------------|
| `terraform workspace list` | List all workspaces; asterisk on current |
| `terraform workspace show` | Print the name of the current workspace |
| `terraform workspace new <name>` | Create a new workspace and switch to it |
| `terraform workspace select <name>` | Switch to an existing workspace |
| `terraform workspace delete <name>` | Delete a workspace (must have empty state) |

---

## Key Concept: Workspace != Environment Isolation

Workspaces look like a clean solution for multi-environment management, but they have a significant limitation: **all workspaces share the same configuration and the same backend**. This means:

| Risk | Explanation |
|------|-------------|
| **State coupling** | All workspace state files live in the same backend bucket/path. A backend misconfiguration or access error affects every environment simultaneously. |
| **Config coupling** | One change to `main.tf` affects all workspaces on the next apply. A typo or mistake in staging can be applied to prod from the same directory. |
| **Access control** | You cannot restrict who can run `terraform workspace select prod` — workspace selection is not an access control mechanism. |
| **Variable drift** | Workspaces share the same `terraform.tfvars`. Managing workspace-specific variable values requires extra tooling (wrapper scripts, CI flags, etc.). |

### When Workspaces ARE Appropriate

| Use case | Why workspaces work here |
|----------|--------------------------|
| **Feature branch testing** | Create a workspace named after your Git branch, test your changes, delete it when done |
| **Temporary parallel environments** | Spin up a copy of an environment for a demo or load test |
| **Small teams with a single backend** | When the team is small enough that shared backend access is acceptable |
| **Non-production tiering** | Dev and staging workspaces are fine; adding prod to the same workspace tree is where risk increases |

### When to Use Separate Directories Instead

Large teams managing production infrastructure typically prefer the **separate directory per environment** pattern:

```
infrastructure/
├── dev/
│   ├── main.tf      ← copy of config, may diverge from staging/prod
│   ├── backend.tf   ← points to dev S3 bucket / key
│   └── terraform.tfvars
├── staging/
│   ├── main.tf
│   ├── backend.tf   ← points to staging S3 bucket / key
│   └── terraform.tfvars
└── prod/
    ├── main.tf
    ├── backend.tf   ← points to prod S3 bucket / key
    └── terraform.tfvars
```

Benefits of separate directories:
- Each environment has its own backend — a staging state corruption cannot affect prod.
- IAM/RBAC can restrict who can run Terraform in the `prod/` directory (e.g., only CI/CD).
- Config changes can be promoted gradually: dev → staging → prod with PR reviews at each step.

The Terraform team's own guidance (and HashiCorp's Terraform Best Practices) recommends separate directories (and ideally separate accounts) for production. Workspaces are a lightweight alternative suitable for lower-stakes use cases.

---

## Key Concepts Summary

| Concept | Takeaway |
|---------|---------|
| `terraform.workspace` | Built-in variable containing the active workspace name — use it in filenames, tags, config lookups |
| State isolation | Each workspace has its own state; resources in one workspace are invisible to another |
| `terraform.tfstate.d/` | Directory that holds state for all non-default workspaces |
| Default workspace | Always exists; always at `./terraform.tfstate`; cannot be deleted |
| Workspace vs directory | Workspaces share backend and config — directories provide stronger isolation |
| Destroy before delete | Must `terraform destroy` in a workspace before `terraform workspace delete` it |
| Workspace selection | `terraform workspace select <name>` — recorded in `.terraform/environment` |

---

*End of Lab 036*
