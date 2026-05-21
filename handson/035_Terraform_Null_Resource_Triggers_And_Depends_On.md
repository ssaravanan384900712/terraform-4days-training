# 035 — Terraform: null_resource, Triggers & depends_on

**By: Saravanan Sundaramoorthy**
**Environment:** Local (no cloud credentials needed)
**Time to complete:** ~10 minutes

---

## Topic

| Concept | What it means |
|---------|--------------|
| **`null_resource`** | A resource with no real infrastructure — exists only to run provisioners or enforce ordering |
| **`provisioner "local-exec"`** | Runs a shell command on the machine where Terraform executes |
| **`triggers`** | A map of values; Terraform destroys and re-creates `null_resource` whenever any value changes |
| **`depends_on`** | Forces an explicit ordering between resources that Terraform cannot infer automatically |
| **`terraform_data`** | The modern replacement for `null_resource`, available since Terraform 1.4 — no extra provider needed |

`null_resource` is a "fake" resource. It creates no VMs, no files, no cloud objects. Its entire job is one of two things:

1. **Run side-effects** — shell commands, scripts, configuration steps — via `local-exec` or `remote-exec` provisioners.
2. **Enforce ordering** — tell Terraform "do this before that" when the dependency cannot be expressed through resource attribute references.

The `triggers` map is the on/off switch. Change any value in the map and Terraform destroys the old `null_resource` and creates a new one — re-running the provisioner in the process.

> **Note — null_resource is deprecated.** In Terraform 1.4+ the built-in `terraform_data` resource replaces it. It needs no provider block and no `hashicorp/null` entry in `required_providers`. This lab shows both so you can read old code and write new code confidently.

---

## What We Will Build

Three isolated demonstrations in one working project:

| Demo | What it shows |
|------|--------------|
| **Demo 1** | `null_resource` with `timestamp()` trigger — re-runs on every apply |
| **Demo 2** | `depends_on` ordering — null_resource waits for a `local_file` to exist |
| **Demo 3** | Version-controlled trigger — only re-runs when `app_version` variable changes |

Plus a **Demo 4** that rewrites Demo 1 using the modern `terraform_data` resource for a side-by-side comparison.

---

## Directory Layout

```
~/terraform-null-035/
├── providers.tf
├── variables.tf
├── main.tf
└── outputs.tf
```

---

## Step 1 — Create the Project Directory

```bash
mkdir ~/terraform-null-035
cd ~/terraform-null-035
```

---

## Step 2 — providers.tf

```hcl
# providers.tf
terraform {
  required_version = ">= 1.4"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# No provider configuration blocks are needed.
# null and local providers work without any credentials.
```

> Why `>= 1.4`? That is the minimum version that includes the built-in `terraform_data` resource used in Demo 4. If you are on an older version, remove the `terraform_data` block and everything else still works.

---

## Step 3 — variables.tf

```hcl
# variables.tf

variable "app_version" {
  description = "Application version string. Change this to trigger the deploy null_resource."
  type        = string
  default     = "1.0.0"
}

variable "owner" {
  description = "Owner tag embedded in generated files."
  type        = string
  default     = "saravanans"
}

variable "site" {
  description = "Site name embedded in generated files."
  type        = string
  default     = "robochef.co"
}
```

---

## Step 4 — main.tf

```hcl
# main.tf

###############################################################
# DEMO 1 — null_resource with timestamp() trigger
#
# timestamp() returns the current UTC time as a string.
# Because the trigger value changes on every plan, Terraform
# always considers this resource "changed" and re-creates it —
# which re-runs the local-exec provisioner on every apply.
#
# Use case: "I want this shell command to run every time I apply."
###############################################################

resource "null_resource" "greet" {
  triggers = {
    always_run = timestamp()   # new value on every plan → always re-creates
  }

  provisioner "local-exec" {
    command = "echo 'Hello from ${var.site} at $(date)' > /tmp/robochef-greeting.txt"
  }
}


###############################################################
# DEMO 2 — depends_on: null_resource waits for local_file
#
# local_file.config writes a JSON file to /tmp/.
# null_resource.process_config must run AFTER that file exists.
#
# Terraform can infer dependencies from attribute references
# (e.g., referencing local_file.config.filename inside the
# null_resource would be enough). But provisioner commands are
# opaque strings — Terraform cannot see that the command reads
# the file. So we use explicit depends_on to be safe.
###############################################################

resource "local_file" "config" {
  filename        = "/tmp/robochef-config.json"
  file_permission = "0644"
  content = jsonencode({
    site    = var.site
    owner   = var.owner
    version = var.app_version
    note    = "Written by Terraform local_file resource"
  })
}

resource "null_resource" "process_config" {
  # explicit dependency — Terraform will not start this resource
  # until local_file.config has been created successfully.
  depends_on = [local_file.config]

  triggers = {
    # Re-run whenever the config file content changes.
    # We use the file content hash as the trigger value.
    config_content = local_file.config.content
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "--- Config file contents ---"
      cat /tmp/robochef-config.json
      echo ""
      echo "Config processed for ${var.site}!"
    EOT
  }
}


###############################################################
# DEMO 3 — trigger on variable change only
#
# Unlike Demo 1, this trigger is tied to var.app_version.
# The null_resource is only re-created (and the provisioner
# re-run) when you change the variable value.
#
# First apply  → creates, runs provisioner
# Second apply (same version) → no change, provisioner skipped
# Apply with -var="app_version=1.1.0" → re-creates, runs again
###############################################################

resource "null_resource" "deploy" {
  triggers = {
    version = var.app_version   # only changes when app_version changes
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Deploying ${var.site} version ${var.app_version}"
      echo "Deploy timestamp: $(date)"
      echo "${var.app_version}" > /tmp/robochef-deployed-version.txt
      echo "Deployment complete."
    EOT
  }
}


###############################################################
# DEMO 4 — terraform_data (modern replacement for null_resource)
#
# terraform_data is a built-in resource introduced in Terraform 1.4.
# It works identically to null_resource but:
#   - No provider needed (no hashicorp/null in required_providers)
#   - The trigger map is called "triggers_replace" (not "triggers")
#   - It can also store arbitrary "input" values in state
#
# This block does the same job as null_resource.greet in Demo 1.
###############################################################

resource "terraform_data" "greet_modern" {
  triggers_replace = {
    always_run = timestamp()   # same pattern — re-runs every apply
  }

  provisioner "local-exec" {
    command = "echo 'Hello from ${var.site} (terraform_data) at $(date)' > /tmp/robochef-greeting-modern.txt"
  }
}

# terraform_data also accepts an "input" value that is stored in state
# and exposed as the "output" attribute. Useful for passing computed
# values through the resource lifecycle without a separate output block.
resource "terraform_data" "version_store" {
  input = {
    site    = var.site
    version = var.app_version
    owner   = var.owner
  }
}
```

---

## Step 5 — outputs.tf

```hcl
# outputs.tf

output "greeting_file" {
  description = "Path to the greeting file written by Demo 1"
  value       = "/tmp/robochef-greeting.txt"
}

output "config_file" {
  description = "Path to the JSON config file written by Demo 2"
  value       = local_file.config.filename
}

output "deployed_version" {
  description = "The app version that was deployed in Demo 3"
  value       = null_resource.deploy.triggers.version
}

output "modern_greeting_file" {
  description = "Path to the greeting file written by Demo 4 (terraform_data)"
  value       = "/tmp/robochef-greeting-modern.txt"
}

output "version_store_output" {
  description = "The input value stored inside terraform_data.version_store"
  value       = terraform_data.version_store.output
}
```

---

## Step 6 — Init and First Apply

```bash
cd ~/terraform-null-035

terraform init
```

Expected output (abbreviated):

```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/null versions matching "~> 3.0"...
- Finding hashicorp/local versions matching "~> 2.0"...
- Installing hashicorp/null v3.2.3...
- Installing hashicorp/local v2.5.2...
Terraform has been successfully initialized!
```

```bash
terraform plan
```

You will see four resources to create:

```
  + null_resource.greet
  + local_file.config
  + null_resource.process_config
  + null_resource.deploy
  + terraform_data.greet_modern
  + terraform_data.version_store

Plan: 6 to add, 0 to change, 0 to destroy.
```

Notice the ordering in the plan output — `local_file.config` appears before `null_resource.process_config` because of the `depends_on`. Terraform will not show a dependency arrow in text output, but the sequencing in the apply output will confirm it.

```bash
terraform apply -auto-approve
```

Expected output (abbreviated — provisioner output is mixed in):

```
null_resource.greet: Creating...
null_resource.deploy: Creating...
local_file.config: Creating...
terraform_data.greet_modern: Creating...
null_resource.greet: Provisioning with 'local-exec'...
null_resource.greet (local-exec): Executing: ["/bin/sh" "-c" "echo 'Hello from robochef.co at Thu May 21 ...' > /tmp/robochef-greeting.txt"]
null_resource.deploy: Provisioning with 'local-exec'...
null_resource.deploy (local-exec): Deploying robochef.co version 1.0.0
null_resource.deploy (local-exec): Deploy timestamp: Thu May 21 ...
null_resource.deploy (local-exec): Deployment complete.
local_file.config: Creation complete after 0s [id=...]
null_resource.process_config: Creating...
null_resource.process_config: Provisioning with 'local-exec'...
null_resource.process_config (local-exec): --- Config file contents ---
null_resource.process_config (local-exec): {"note":"Written by Terraform local_file resource","owner":"saravanans","site":"robochef.co","version":"1.0.0"}
null_resource.process_config (local-exec): Config processed for robochef.co!
...
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:
config_file          = "/tmp/robochef-config.json"
deployed_version     = "1.0.0"
greeting_file        = "/tmp/robochef-greeting.txt"
modern_greeting_file = "/tmp/robochef-greeting-modern.txt"
version_store_output = tomap({
  "owner"   = "saravanans"
  "site"    = "robochef.co"
  "version" = "1.0.0"
})
```

Confirm the files were written:

```bash
cat /tmp/robochef-greeting.txt
cat /tmp/robochef-config.json
cat /tmp/robochef-deployed-version.txt
cat /tmp/robochef-greeting-modern.txt
```

---

## Step 7 — Apply Again (Same Values)

Run apply a second time without changing anything:

```bash
terraform apply -auto-approve
```

Expected output — watch carefully:

```
null_resource.greet: Destroying...  (tainted by trigger change)
null_resource.greet: Creating...
null_resource.greet: Provisioning with 'local-exec'...
null_resource.greet (local-exec): Executing: ...

terraform_data.greet_modern: Destroying...
terraform_data.greet_modern: Creating...
terraform_data.greet_modern: Provisioning with 'local-exec'...

Apply complete! Resources: 2 added, 0 changed, 2 destroyed.
```

Key observations:
- `null_resource.greet` and `terraform_data.greet_modern` were **destroyed and re-created** because `timestamp()` produced a new value — their `triggers` / `triggers_replace` changed.
- `null_resource.deploy` was **not touched** because `var.app_version` is still `"1.0.0"`.
- `null_resource.process_config` was **not touched** because `local_file.config.content` did not change.
- `local_file.config` was **not touched** — same content.

This demonstrates the difference between a "run every time" trigger (`timestamp()`) and a "run only when value changes" trigger (`var.app_version`).

---

## Step 8 — Trigger the Deploy by Changing app_version

Now simulate releasing a new version:

```bash
terraform apply -auto-approve -var="app_version=1.1.0"
```

Expected output:

```
null_resource.greet: Destroying... [trigger changed]
null_resource.greet: Creating...
null_resource.deploy: Destroying... [trigger version changed: 1.0.0 -> 1.1.0]
null_resource.deploy: Creating...
null_resource.deploy: Provisioning with 'local-exec'...
null_resource.deploy (local-exec): Deploying robochef.co version 1.1.0
null_resource.deploy (local-exec): Deploy timestamp: Thu May 21 ...
null_resource.deploy (local-exec): Deployment complete.
local_file.config: Modifying... [content changed]
null_resource.process_config: Destroying... [trigger config_content changed]
null_resource.process_config: Creating...
null_resource.process_config (local-exec): --- Config file contents ---
null_resource.process_config (local-exec): {"note":"...","owner":"saravanans","site":"robochef.co","version":"1.1.0"}
null_resource.process_config (local-exec): Config processed for robochef.co!
...
Apply complete! Resources: 4 added, 1 changed, 4 destroyed.
```

Notice:
- `null_resource.deploy` fired because its trigger (`version`) changed from `1.0.0` to `1.1.0`.
- `local_file.config` was modified in-place (the `content` attribute changed).
- `null_resource.process_config` re-ran because its trigger (`config_content`) reflects the new file content.
- The deploy output confirms it printed `version 1.1.0`.

Verify:

```bash
cat /tmp/robochef-deployed-version.txt   # should show 1.1.0
cat /tmp/robochef-config.json            # should show "version":"1.1.0"
```

---

## Step 9 — Apply Again Without Changing Version

Apply again with the same version to confirm the deploy provisioner does NOT re-run:

```bash
terraform apply -auto-approve -var="app_version=1.1.0"
```

Only `null_resource.greet` and `terraform_data.greet_modern` change (timestamp triggers). Everything else is stable:

```
null_resource.greet: Destroying... [trigger changed]
null_resource.greet: Creating...
terraform_data.greet_modern: Destroying...
terraform_data.greet_modern: Creating...

Apply complete! Resources: 2 added, 0 changed, 2 destroyed.
```

The deploy provisioner is silent — it only runs when `app_version` changes.

---

## Step 10 — Inspect the State File

```bash
terraform show
```

Look for the `null_resource.deploy` block — you will see the triggers map stored in state:

```
# null_resource.deploy:
resource "null_resource" "deploy" {
  id = "1234567890123456789"
  triggers = {
    "version" = "1.1.0"
  }
}
```

Terraform uses this stored value to compare against the next plan. When you apply with `app_version=1.2.0`, Terraform sees `"1.1.0"` in state vs `"1.2.0"` in config — detects a change — and re-creates.

```bash
# See the raw state JSON for null_resource.deploy
terraform state show null_resource.deploy

# List all resources in state
terraform state list
```

---

## Step 11 — Observe depends_on in the Plan Graph

The Terraform plan processes resources in dependency order. You can visualize this:

```bash
terraform graph | head -40
```

This outputs DOT-format graph text. You will see edges like:

```
"null_resource.process_config" -> "local_file.config"
```

That edge was created by our `depends_on = [local_file.config]`. Even if we removed the `triggers` reference to `local_file.config.content`, the ordering would still be enforced.

If you have `graphviz` installed you can render it:

```bash
terraform graph | dot -Tsvg > /tmp/robochef-null-graph.svg
# then open /tmp/robochef-null-graph.svg in a browser
```

---

## Step 12 — null_resource vs terraform_data Side-by-Side

| Feature | `null_resource` | `terraform_data` |
|---------|----------------|-----------------|
| Provider required | Yes — `hashicorp/null` | No — built-in |
| Trigger argument | `triggers = {}` | `triggers_replace = {}` |
| Store values in state | No | Yes — `input` / `output` attributes |
| Supports provisioners | Yes | Yes |
| Minimum Terraform version | Any | 1.4+ |
| Status | Deprecated | Current/recommended |

When you read old Terraform code (tutorials, Stack Overflow, company repos) you will see `null_resource` everywhere. When you write new code, prefer `terraform_data`.

The migration is mechanical:

```hcl
# OLD
resource "null_resource" "example" {
  triggers = { key = "value" }
  provisioner "local-exec" { command = "echo hello" }
}

# NEW (Terraform 1.4+)
resource "terraform_data" "example" {
  triggers_replace = { key = "value" }
  provisioner "local-exec" { command = "echo hello" }
}
```

Remove `hashicorp/null` from `required_providers` once all `null_resource` blocks are migrated.

---

## Step 13 — Destroy

```bash
terraform destroy -auto-approve
rm -rf .terraform
```

Expected:

```
null_resource.greet: Destroying...
null_resource.process_config: Destroying...
null_resource.deploy: Destroying...
local_file.config: Destroying...
terraform_data.greet_modern: Destroying...
terraform_data.version_store: Destroying...

Destroy complete! Resources: 6 destroyed.
```

The `/tmp/` files are NOT removed by destroy — `local-exec` provisioners do not run destroy-time cleanup unless you add a `when = destroy` block:

```hcl
# Optional: run a command on destroy
provisioner "local-exec" {
  when    = destroy
  command = "rm -f /tmp/robochef-greeting.txt"
}
```

Clean up manually if desired:

```bash
rm -f /tmp/robochef-greeting.txt \
      /tmp/robochef-greeting-modern.txt \
      /tmp/robochef-config.json \
      /tmp/robochef-deployed-version.txt
```

---

## Key Concepts Summary

| Concept | Takeaway |
|---------|---------|
| `null_resource` purpose | Run provisioners and enforce ordering — no real infrastructure created |
| `triggers = { always_run = timestamp() }` | Re-runs provisioner on every apply — useful for scripts that must always execute |
| `triggers = { version = var.app_version }` | Re-runs provisioner only when the named variable changes — useful for deploy steps |
| `depends_on` | Forces sequential ordering when Terraform cannot infer it from attribute references |
| Provisioner output | Appears in `terraform apply` output in real time — good for debug/audit |
| `terraform_data` | Terraform 1.4+ built-in; same job, no provider needed, adds `input`/`output` storage |
| Provisioner philosophy | Provisioners are a last resort — prefer dedicated resources when possible |

---

## When to Use null_resource / terraform_data

**Good uses:**
- Running a one-time database seed script after an RDS instance is ready
- Invoking a deployment script that has no Terraform resource equivalent
- Waiting for an external system to become healthy before proceeding
- Chaining resources that have no natural attribute-level dependency

**Avoid when:**
- A proper resource type exists (use `aws_s3_object` instead of `local-exec aws s3 cp`)
- The provisioner logic is complex — move it to a script file and call that instead
- You need idempotency guarantees — provisioners have none

---

*End of Lab 035*
