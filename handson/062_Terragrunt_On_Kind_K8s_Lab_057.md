# Lab 062 — Terragrunt Applied to the kind Kubernetes Lab (057)

**By: Saravanan Sundaramoorthy**
**Environment:** Ubuntu Linux — requires kind v0.23.0, kubectl, Terraform ≥ 1.3, Terragrunt ≥ 0.68
**Prerequisites:** Lab 057 completed — `~/terraform-kind-057-demo/` must exist
**Time:** ~25 minutes

---

## What You'll Learn

| Topic | Concept |
|-------|---------|
| Terragrunt | DRY wrapper around Terraform — call one module from many environments |
| `source` | Point to an existing Terraform module without copying `.tf` files |
| `find_in_parent_folders()` | Inherit shared config from a root `terragrunt.hcl` |
| `run-all apply` | Apply every environment in the stack with one command |
| `dependency {}` | Reference outputs from one Terragrunt unit inside another |
| State isolation | Each unit gets its own state file — dev and prod never share state |

---

## Introduction to Terragrunt

When you have one Terraform module and need to deploy it to **multiple environments** (dev, staging, prod), the naive approach is to copy the `.tf` files into each environment directory. You end up with identical `versions.tf`, `providers.tf`, and `backend.tf` in every folder — a maintenance nightmare where a one-line provider version bump requires editing three directories.

**Terragrunt** is a thin wrapper around Terraform by Gruntwork that enforces DRY (Don't Repeat Yourself) configuration. Instead of copying `.tf` files, you write a `terragrunt.hcl` in each environment that only specifies what **differs** between environments:

```
Without Terragrunt                        With Terragrunt
──────────────────────────────────        ───────────────────────────────────────────
dev/
  main.tf          ← module call          terragrunt-root/
  versions.tf      ← identical              terragrunt.hcl     ← shared: provider, backend
  providers.tf     ← identical              dev/
  terraform.tfvars ← env-specific            terragrunt.hcl   ← only: inputs = { replicas=1 }
staging/                                   prod/
  main.tf          ← copy of dev             terragrunt.hcl   ← only: inputs = { replicas=3 }
  versions.tf      ← copy
  providers.tf     ← copy
  terraform.tfvars ← env-specific
prod/
  (same again)
```

Key Terragrunt ideas:

| Concept | Meaning |
|---------|---------|
| `source` | Points to a Terraform module directory — no `.tf` duplication needed |
| `find_in_parent_folders()` | Walks up to find the root `terragrunt.hcl` — inherits shared config |
| `inputs = {}` | Passed as `-var` flags to Terraform — replaces `terraform.tfvars` |
| `run-all apply` | Applies every unit in the stack; respects `dependency {}` ordering |
| `dependency {}` | Cross-unit output reference — like a `data` source across state files |
| `.terragrunt-cache` | Terragrunt copies the source module here — one isolated copy per unit |
| State isolation | Every unit has its own state file — dev and prod never share state |

---

## Step 1 — Install Terragrunt

```bash
# Linux amd64
curl -Lo /tmp/terragrunt \
  https://github.com/gruntwork-io/terragrunt/releases/download/v0.68.0/terragrunt_linux_amd64
chmod +x /tmp/terragrunt
sudo mv /tmp/terragrunt /usr/local/bin/terragrunt
terragrunt --version
# terragrunt version v0.68.0
```

---

## Step 2 — Project Layout

```
~/terragrunt-kind-062-demo/
├── terragrunt.hcl              ← root: shared locals and inputs
├── dev/
│   └── terragrunt.hcl          ← dev environment: app_name=robochef-dev, replicas=1
└── prod/
    └── terragrunt.hcl          ← prod environment: app_name=robochef-prod, replicas=3
```

The **source module** is the existing lab 057 project at `~/terraform-kind-057-demo/`. Terragrunt calls it via a relative `source` path — no need to duplicate any `.tf` files.

```bash
mkdir -p ~/terragrunt-kind-062-demo/dev
mkdir -p ~/terragrunt-kind-062-demo/prod
cd ~/terragrunt-kind-062-demo
```

---

## Step 3 — Root `terragrunt.hcl`

```hcl
# ~/terragrunt-kind-062-demo/terragrunt.hcl

locals {
  owner   = "saravanans"
  project = "robochef.co"
}

# Shared inputs inherited by every child unit
inputs = {
  owner = local.owner
}
```

---

## Step 4 — `dev/terragrunt.hcl`

```hcl
# ~/terragrunt-kind-062-demo/dev/terragrunt.hcl

terraform {
  # source points at the lab-057 module (the existing project directory)
  # The trailing // tells Terragrunt this is the module root
  source = "../../terraform-kind-057-demo//"
}

# Pull in shared config from the root terragrunt.hcl
include "root" {
  path = find_in_parent_folders()
}

inputs = {
  app_name = "robochef-dev"
  replicas = 1
}
```

---

## Step 5 — `prod/terragrunt.hcl`

```hcl
# ~/terragrunt-kind-062-demo/prod/terragrunt.hcl

terraform {
  source = "../../terraform-kind-057-demo//"
}

include "root" {
  path = find_in_parent_folders()
}

inputs = {
  app_name = "robochef-prod"
  replicas = 3
}
```

---

## Step 6 — Apply a Single Environment

Make sure the kind cluster is running first:

```bash
kind get clusters
# terraform-kind-lab   ← must be present
```

If not running:
```bash
kind create cluster --name terraform-kind-lab --wait 60s
```

Apply just `dev`:

```bash
cd ~/terragrunt-kind-062-demo/dev
terragrunt apply --auto-approve
```

Expected:
```
[terragrunt] Copying files from ../../terraform-kind-057-demo into .terragrunt-cache/...
[terragrunt] Running command: terraform apply -auto-approve

kubernetes_namespace.app: Creating...
kubernetes_namespace.app: Creation complete after 0s [id=robochef-dev]
kubernetes_config_map.app: Creating...
kubernetes_service.app: Creating...
kubernetes_config_map.app: Creation complete after 0s [id=robochef-dev/robochef-dev-config]
kubernetes_service.app: Creation complete after 0s [id=robochef-dev/robochef-dev-service]
kubernetes_deployment.app: Creating...
kubernetes_deployment.app: Creation complete after 14s [id=robochef-dev/robochef-dev-deployment]

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:
deployment_name = "robochef-dev-deployment"
namespace       = "robochef-dev"
replicas        = "1"
service_name    = "robochef-dev-service"
```

```bash
kubectl get pods -n robochef-dev --context kind-terraform-kind-lab
# NAME                                           READY   STATUS    RESTARTS   AGE
# robochef-dev-deployment-xxxxxxxxx-zzzzz        1/1     Running   0          20s
```

---

## Step 7 — Apply All Environments at Once

```bash
cd ~/terragrunt-kind-062-demo
terragrunt run-all apply --auto-approve
```

Expected:
```
[terragrunt] Stack at /home/saravanans/terragrunt-kind-062-demo:
  => Module dev  (running)
  => Module prod (running)

[terragrunt] [dev]  Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
[terragrunt] [prod] Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
```

Verify both namespaces and pod counts:

```bash
kubectl get namespaces | grep robochef
# robochef-dev    Active   30s
# robochef-prod   Active   28s

kubectl get pods -n robochef-dev  --context kind-terraform-kind-lab
# 1 pod

kubectl get pods -n robochef-prod --context kind-terraform-kind-lab
# 3 pods
```

---

## Step 8 — State Isolation

Each Terragrunt unit has its own `.terragrunt-cache/<hash>/terraform.tfstate`. Dev and prod states are completely independent:

```bash
find ~/terragrunt-kind-062-demo -name "terraform.tfstate" 2>/dev/null
# .../dev/.terragrunt-cache/.../terraform.tfstate
# .../prod/.terragrunt-cache/.../terraform.tfstate
```

A change to `prod` never touches the `dev` state, and `terraform plan` in one unit never reads the other's state.

---

## Step 9 — Override at Runtime

```bash
cd ~/terragrunt-kind-062-demo/prod
terragrunt apply --auto-approve -var="replicas=5"

kubectl get pods -n robochef-prod --context kind-terraform-kind-lab
# 5 pods now running
```

Scale back:

```bash
terragrunt apply --auto-approve
# back to replicas=3 as defined in terragrunt.hcl
```

---

## Step 10 — `dependency {}` Block (Bonus)

If `prod` needed an output from `dev` (e.g., a shared namespace or config value), add a `dependency` block. This is the Terragrunt equivalent of a `data` source across state files:

```hcl
# prod/terragrunt.hcl — shows the dependency pattern

dependency "dev" {
  config_path = "../dev"

  # Returned when dev state doesn't exist yet — prevents failure during plan
  mock_outputs = {
    namespace = "robochef-dev-mock"
  }
}

inputs = {
  app_name      = "robochef-prod"
  replicas      = 3
  dev_namespace = dependency.dev.outputs.namespace   # cross-unit reference
}
```

With this in place, `run-all` automatically applies `dev` first, then `prod`:

```bash
terragrunt run-all apply --auto-approve
# [dev]  Apply complete!   ← applied first (prod depends on it)
# [prod] Apply complete!   ← applied second
```

And `run-all destroy` reverses the order automatically:

```bash
terragrunt run-all destroy --auto-approve
# [prod] Destroy complete!  ← destroyed first
# [dev]  Destroy complete!  ← destroyed second
```

---

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| **`source = "path//"`** | Relative path to the Terraform module; `//` marks the module root |
| **`find_in_parent_folders()`** | Walks up to find root `terragrunt.hcl` — all child units inherit its `inputs` and `locals` |
| **`inputs = {}`** | Passed as `-var key=value` flags — equivalent to `terraform.tfvars` but per-unit |
| **`run-all apply`** | Applies the whole stack; runs units in parallel unless `dependency {}` requires ordering |
| **`dependency {}`** | References another unit's outputs — Terragrunt reads the remote state of that unit |
| **`mock_outputs`** | Fallback values used during `plan` when the dependency hasn't been applied yet |
| **`.terragrunt-cache`** | Terragrunt copies the source module here before each run — never modifies the original |
| **State isolation** | Each unit has its own `.tfstate` — environments never pollute each other |

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `find_in_parent_folders: could not find terragrunt.hcl` | Root `terragrunt.hcl` missing | Ensure `~/terragrunt-kind-062-demo/terragrunt.hcl` exists |
| `source module not found` | Relative `source` path resolves incorrectly | Run `pwd` inside the unit dir and verify `../../terraform-kind-057-demo` exists |
| `kind cluster unreachable` | kind cluster not running | `kind create cluster --name terraform-kind-lab --wait 60s` |
| `dependency output not found` | Dependency unit not yet applied | Apply dependency first, or add `mock_outputs` for plan-time safety |
| Stale cache after source changes | `.terragrunt-cache` has old copy | Add `--terragrunt-source-update` flag to force re-copy |

---

## Cleanup

```bash
# Destroy all environments
cd ~/terragrunt-kind-062-demo
terragrunt run-all destroy --auto-approve

# Remove cache directories
rm -rf ~/terragrunt-kind-062-demo/dev/.terragrunt-cache
rm -rf ~/terragrunt-kind-062-demo/prod/.terragrunt-cache

# Delete the kind cluster
kind delete cluster --name terraform-kind-lab
```

---

## Concept Summary

```
terragrunt-kind-062-demo/
  terragrunt.hcl              ← root: locals { owner, project }, shared inputs
  dev/terragrunt.hcl          ← source = lab-057 module, replicas=1, app=robochef-dev
  prod/terragrunt.hcl         ← source = lab-057 module, replicas=3, app=robochef-prod

terragrunt apply              → single environment
terragrunt run-all apply      → all environments in parallel (or ordered by dependency)

find_in_parent_folders()      → child inherits root inputs without copy-paste
dependency {}                 → cross-unit output reference, apply/destroy order enforced
.terragrunt-cache             → isolated copy per unit, never touches the source module
state isolation               → dev and prod never share terraform.tfstate
```
