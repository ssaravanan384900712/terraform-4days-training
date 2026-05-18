# Hands-On 1.2 — Terraform Lifecycle: init, plan, apply, destroy

**Directory:** `lab-lifecycle/`

---

## Concept

Every Terraform workflow follows the same 4-step lifecycle. Before you write a single resource, you need to understand what each step does, what files it creates, and why.

```
┌─────────────────────────────────────────────────────────┐
│                  Terraform Lifecycle                      │
│                                                          │
│   ┌──────┐    ┌──────┐    ┌───────┐    ┌─────────┐     │
│   │ init │───►│ plan │───►│ apply │───►│ destroy │     │
│   └──────┘    └──────┘    └───────┘    └─────────┘     │
│      │           │            │             │            │
│      ▼           ▼            ▼             ▼            │
│  Downloads    Shows       Executes      Removes         │
│  providers    preview     changes       everything      │
│  + modules    of changes  on target     from target     │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### What Happens at Each Stage

| Command | What It Does | Creates/Modifies |
|---------|-------------|-----------------|
| `terraform init` | Downloads providers, initializes backend | `.terraform/`, `.terraform.lock.hcl` |
| `terraform plan` | Compares desired state (code) vs actual state | Nothing — read-only preview |
| `terraform apply` | Executes the plan, provisions resources | `terraform.tfstate` |
| `terraform destroy` | Removes all managed resources | Updates `terraform.tfstate` |

---

## Step-by-Step: Understanding Every File and Directory

### Step 1 — Create a fresh project

```bash
mkdir -p ~/labs/lab-lifecycle
cd ~/labs/lab-lifecycle
```

### Step 2 — Write the simplest possible Terraform config

Create `main.tf`:

```hcl
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
  required_version = ">= 1.5.0"
}

resource "local_file" "demo" {
  content  = "Hello from Terraform lifecycle demo!"
  filename = "${path.module}/output/demo.txt"
}
```

### Step 3 — Examine the directory BEFORE init

```bash
ls -la
```

Expected output:

```
total 4
drwxr-xr-x 2 user user 4096 ... .
drwxr-xr-x 3 user user 4096 ... ..
-rw-r--r-- 1 user user  243 ... main.tf
```

> **Key point:** Right now there's only your code. No providers, no state, no lock file. Terraform can't do anything yet.

---

## The `terraform init` Command — Deep Dive

### Step 4 — Run terraform init

```bash
terraform init
```

Expected output:

```
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/local versions matching "~> 2.0"...
- Installing hashicorp/local v2.5.2...
- Installed hashicorp/local v2.5.2 (signed by HashiCorp)

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!
```

### Step 5 — Examine what init created

```bash
ls -la
```

Expected output:

```
total 12
drwxr-xr-x 3 user user 4096 ... .
drwxr-xr-x 3 user user 4096 ... ..
drwxr-xr-x 3 user user 4096 ... .terraform
-rw-r--r-- 1 user user 1234 ... .terraform.lock.hcl
-rw-r--r-- 1 user user  243 ... main.tf
```

Two new things appeared: `.terraform/` directory and `.terraform.lock.hcl` file.

### Step 6 — Explore the .terraform directory

```bash
find .terraform -type f
```

Expected output:

```
.terraform/providers/registry.terraform.io/hashicorp/local/2.5.2/linux_amd64/terraform-provider-local_v2.5.2_x5
```

```
.terraform/ Directory Structure
├── providers/
│   └── registry.terraform.io/
│       └── hashicorp/
│           └── local/
│               └── 2.5.2/
│                   └── linux_amd64/
│                       └── terraform-provider-local_v2.5.2_x5  ← The actual binary
└── (modules/ would appear here if you used modules)
```

> **What is .terraform/?**
> - Contains **downloaded provider binaries** (plugins that talk to APIs)
> - Contains **downloaded modules** (if you use `module` blocks)
> - **Never commit this to git** — it's like `node_modules/` in JavaScript
> - Can be safely deleted — `terraform init` recreates it
> - Size can be large (AWS provider alone is ~400MB)

### Step 7 — Examine the lock file

```bash
cat .terraform.lock.hcl
```

Expected output:

```hcl
# This file is maintained automatically by "terraform init".
# Manual edits may be lost in future updates.

provider "registry.terraform.io/hashicorp/local" {
  version     = "2.5.2"
  constraints = "~> 2.0"
  hashes = [
    "h1:JlMZD6nYqJ8sSj...",
    "zh:136299545178ce...",
    ...
  ]
}
```

> **What is .terraform.lock.hcl?**
> - Locks the **exact provider version** and **checksums** (hashes)
> - Like `package-lock.json` (npm) or `Gemfile.lock` (Ruby)
> - **DO commit this to git** — ensures team uses same provider versions
> - Prevents supply-chain attacks (hash verification)
> - Updated by `terraform init -upgrade`

### Quick Reference: What to commit vs ignore

| File/Directory | Git? | Why |
|---------------|------|-----|
| `*.tf` | ✅ Commit | Your infrastructure code |
| `.terraform.lock.hcl` | ✅ Commit | Locks provider versions for team |
| `.terraform/` | ❌ Ignore | Downloaded binaries (large, regenerated by init) |
| `terraform.tfstate` | ❌ Ignore | Contains secrets, use remote backend |
| `terraform.tfstate.backup` | ❌ Ignore | Previous state backup |
| `*.tfvars` | ⚠️ Depends | May contain secrets — use .gitignore if so |

---

## The `terraform plan` Command — Deep Dive

### Step 8 — Run terraform plan

```bash
terraform plan
```

Expected output:

```
Terraform used the selected providers to generate the following execution plan.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # local_file.demo will be created
  + resource "local_file" "demo" {
      + content              = "Hello from Terraform lifecycle demo!"
      + content_base64sha256 = (known after apply)
      + content_base64sha512 = (known after apply)
      + content_md5          = (known after apply)
      + content_sha1         = (known after apply)
      + content_sha256       = (known after apply)
      + content_sha512       = (known after apply)
      + directory_permission = "0777"
      + file_permission      = "0777"
      + filename             = "./output/demo.txt"
      + id                   = (known after apply)
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

### Understanding Plan Output Symbols

```
+   create      — Resource will be created (doesn't exist yet)
-   destroy     — Resource will be destroyed (removed from config)
~   update      — Resource will be modified in-place
-/+ replace     — Resource will be destroyed and recreated
<=  read        — Data source will be read
```

### Step 9 — Verify plan created NO files

```bash
ls -la
```

The directory is unchanged — **plan is read-only**. It never modifies anything. It's always safe to run.

> **Key point:** `terraform plan` is like a dry run. Run it as many times as you want. Share the output in code reviews. It shows exactly what WILL happen without doing anything.

### Step 10 — Save a plan to a file

```bash
terraform plan -out=tfplan
```

```bash
ls -la tfplan
```

```
-rw-r--r-- 1 user user 1847 ... tfplan
```

> **Saved plans** are binary files. Use `terraform show tfplan` to read them. Use `terraform apply tfplan` to execute the exact plan without re-prompting.

---

## The `terraform apply` Command — Deep Dive

### Step 11 — Run terraform apply

```bash
terraform apply
```

Expected output:

```
Terraform used the selected providers to generate the following execution plan.

  # local_file.demo will be created
  + resource "local_file" "demo" {
      + content              = "Hello from Terraform lifecycle demo!"
      + filename             = "./output/demo.txt"
      ...
    }

Plan: 1 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

local_file.demo: Creating...
local_file.demo: Creation complete after 0s [id=abc123...]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

### Step 12 — Verify the resource was created

```bash
cat output/demo.txt
```

```
Hello from Terraform lifecycle demo!
```

### Step 13 — Examine the state file

```bash
ls -la terraform.tfstate
```

```
-rw-r--r-- 1 user user 1543 ... terraform.tfstate
```

```bash
cat terraform.tfstate | python3 -m json.tool | head -30
```

Expected output:

```json
{
    "version": 4,
    "terraform_version": "1.9.0",
    "serial": 1,
    "lineage": "abc123-def456-...",
    "outputs": {},
    "resources": [
        {
            "mode": "managed",
            "type": "local_file",
            "name": "demo",
            "provider": "provider[\"registry.terraform.io/hashicorp/local\"]",
            "instances": [
                {
                    "schema_version": 0,
                    "attributes": {
                        "content": "Hello from Terraform lifecycle demo!",
                        "filename": "./output/demo.txt",
                        "id": "abc123..."
                    }
                }
            ]
        }
    ]
}
```

> **What is terraform.tfstate?**
> - A JSON file mapping your code to real resources
> - Terraform's **memory** — it knows what it created
> - Contains **sensitive data** (passwords, IPs, keys) — never commit to git
> - Without state, Terraform can't update or destroy resources
> - In production, store remotely (S3 + DynamoDB) — covered in Day 2

### Step 14 — Explore state with CLI commands

```bash
# List all managed resources
terraform state list
```

```
local_file.demo
```

```bash
# Show details of a specific resource
terraform state show local_file.demo
```

```
# local_file.demo:
resource "local_file" "demo" {
    content              = "Hello from Terraform lifecycle demo!"
    content_base64sha256 = "..."
    content_md5          = "..."
    directory_permission = "0777"
    file_permission      = "0777"
    filename             = "./output/demo.txt"
    id                   = "abc123..."
}
```

### Step 15 — Run apply again (idempotency!)

```bash
terraform apply
```

Expected output:

```
local_file.demo: Refreshing state... [id=abc123...]

No changes. Your infrastructure matches the configuration.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

> **Idempotency:** Running apply when nothing changed does NOTHING. This is a core Terraform principle. Your code describes the desired end state — if reality already matches, no action is taken.

---

## The Update Cycle — Plan Symbols in Action

### Step 16 — Modify the resource (trigger an update)

Edit `main.tf` — change the content:

```hcl
resource "local_file" "demo" {
  content  = "Updated content — version 2!"
  filename = "${path.module}/output/demo.txt"
}
```

### Step 17 — Plan the update

```bash
terraform plan
```

Expected output:

```
local_file.demo: Refreshing state... [id=abc123...]

Terraform used the selected providers to generate the following execution plan.

  # local_file.demo must be replaced
-/+ resource "local_file" "demo" {
      ~ content              = "Hello from Terraform lifecycle demo!" -> "Updated content — version 2!"
      ~ content_base64sha256 = "..." -> (known after apply)
      ~ content_md5          = "..." -> (known after apply)
      ~ id                   = "abc123..." -> (known after apply)
        # (3 unchanged attributes hidden)
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

Notice the symbols:
- `~` means the attribute **changed**
- `-/+` means the resource is **replaced** (destroyed then recreated)
- `->`  shows old value → new value

### Step 18 — Apply the update

```bash
terraform apply -auto-approve
```

> **`-auto-approve`** skips the yes/no prompt. Use for automation/CI. Never use in production without reviewing the plan first.

```bash
cat output/demo.txt
```

```
Updated content — version 2!
```

---

## The `terraform destroy` Command — Deep Dive

### Step 19 — Preview the destruction

```bash
terraform plan -destroy
```

Expected output:

```
  # local_file.demo will be destroyed
  - resource "local_file" "demo" {
      - content              = "Updated content — version 2!" -> null
      - filename             = "./output/demo.txt" -> null
      ...
    }

Plan: 0 to add, 0 to change, 1 to destroy.
```

> The `-` prefix means **destroy**. All attributes show `-> null`.

### Step 20 — Destroy all resources

```bash
terraform destroy
```

Expected output:

```
local_file.demo: Refreshing state... [id=abc123...]

  # local_file.demo will be destroyed
  - resource "local_file" "demo" { ... }

Plan: 0 to add, 0 to change, 1 to destroy.

Do you really want to destroy all resources?
  Enter a value: yes

local_file.demo: Destroying... [id=abc123...]
local_file.demo: Destruction complete after 0s

Destroy complete! Resources: 1 destroyed.
```

### Step 21 — Verify everything is gone

```bash
cat output/demo.txt 2>&1
```

```
cat: output/demo.txt: No such file or directory
```

```bash
terraform state list
```

```
(empty — no resources)
```

```bash
cat terraform.tfstate | python3 -m json.tool
```

```json
{
    "version": 4,
    "terraform_version": "1.9.0",
    "serial": 4,
    "lineage": "abc123...",
    "outputs": {},
    "resources": []
}
```

> State file still exists but `resources` array is empty. The `serial` number incremented with each operation.

---

## Summary: Complete Directory State at Each Stage

```
After init:          After apply:           After destroy:
├── main.tf          ├── main.tf            ├── main.tf
├── .terraform/      ├── .terraform/        ├── .terraform/
│   └── providers/   │   └── providers/     │   └── providers/
├── .terraform.      ├── .terraform.        ├── .terraform.
│   lock.hcl         │   lock.hcl           │   lock.hcl
                     ├── terraform.tfstate  ├── terraform.tfstate (empty)
                     ├── terraform.tfstate  ├── terraform.tfstate.backup
                     │   .backup
                     └── output/
                         └── demo.txt       (deleted)
```

## Quick Reference Card

```
┌──────────────────────────────────────────────────────────┐
│  TERRAFORM LIFECYCLE CHEAT SHEET                          │
│                                                          │
│  terraform init            Download providers + modules  │
│  terraform validate        Check syntax (no API calls)   │
│  terraform fmt             Auto-format .tf files         │
│  terraform plan            Preview changes (read-only)   │
│  terraform plan -out=f     Save plan to file             │
│  terraform apply           Execute changes               │
│  terraform apply f         Execute saved plan            │
│  terraform apply -auto-approve  Skip confirmation        │
│  terraform destroy         Remove all resources          │
│  terraform destroy -target=X  Remove specific resource   │
│  terraform state list      List managed resources        │
│  terraform state show X    Show resource details         │
│  terraform output          Show output values            │
│  terraform console         Interactive expression REPL   │
│  terraform graph           Generate dependency graph     │
└──────────────────────────────────────────────────────────┘
```

---

## Clean Up

```bash
cd ~
rm -rf ~/labs/lab-lifecycle
```

> **Next:** Now that you understand the lifecycle, proceed to **Hands-On 1.2a** to practice with the Local Provider, then **1.2b** for the Random Provider.
