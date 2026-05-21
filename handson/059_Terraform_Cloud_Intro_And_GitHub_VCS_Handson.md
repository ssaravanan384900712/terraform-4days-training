# Lab 059 — Terraform Cloud Introduction and GitHub VCS Hands-On

**By: Saravanan Sundaramoorthy**
**Environment:** Browser (Terraform Cloud) + GitHub + optional local Terraform CLI ≥ 1.3
**Time:** ~45 minutes

---

## What You'll Learn

| Topic | Concept |
|-------|---------|
| Terraform Cloud basics | Remote state, remote runs, team collaboration, audit trail |
| Organization and workspace | The two-level hierarchy that structures every Cloud account |
| VCS-driven workflow | GitHub push → automatic plan → apply in the Cloud UI |
| CLI-driven workflow | `terraform login` + `cloud {}` block → local CLI, remote execution |
| Execution modes | Remote (default), Local, Agent — when to choose each |
| Free providers | `random` and `local` — no cloud credentials, no cost, no IAM to set up |
| State in the Cloud | No local `terraform.tfstate` — state lives in Terraform Cloud |

Providers used: `hashicorp/random` and `hashicorp/local` — zero cloud credentials required.

---

## Concept: What Is Terraform Cloud?

Terraform Cloud (HCP Terraform) is HashiCorp's managed platform that wraps the open-source CLI with:

```
Local workflow (open-source)           Terraform Cloud workflow
────────────────────────────           ──────────────────────────────────────
Developer laptop                       GitHub (code)
  terraform init                            │  push
  terraform plan   ← runs here             ▼
  terraform apply  ← runs here       Terraform Cloud
  terraform.tfstate ← stored here       ├── Plan   ← runs here (remote)
                                         ├── Apply  ← runs here (remote)
                                         └── State  ← stored here (remote)
                                              │
                                         Team members see it in the UI
                                         Audit log records every run
```

Key benefits over the raw CLI:
- **Remote state** — no S3 bucket or locking table to set up manually
- **Remote runs** — plans and applies execute on HashiCorp's infrastructure, not your laptop
- **VCS integration** — a GitHub push triggers a plan automatically
- **Team access** — multiple engineers share one workspace safely
- **Audit trail** — every plan, apply, and state change is logged
- **Free tier** — the Free plan supports unlimited workspaces for up to 500 resources

---

## Concept: Key Components

```
Organization  (e.g. robochef-training)
└── Workspace  (e.g. tf-cloud-059-demo)
    ├── Variables      ← Terraform + environment variables
    ├── Runs           ← Plan → Apply lifecycle
    │   ├── Plan
    │   ├── Cost Estimation  (skipped on free/open-source plan)
    │   └── Apply
    └── States         ← versioned snapshots of terraform.tfstate
```

| Level | What it is | Analogy |
|-------|-----------|---------|
| Organization | Top-level account grouping | GitHub organization |
| Workspace | One Terraform root module's lifecycle | GitHub repository |
| Run | One plan+apply cycle | CI pipeline run |
| State | Snapshot of managed infrastructure | `terraform.tfstate` file |

---

## Concept: VCS-Driven vs CLI-Driven Workflow

| Feature | VCS-Driven | CLI-Driven |
|---------|-----------|-----------|
| Trigger | `git push` to GitHub | `terraform apply` on local terminal |
| Plan location | Terraform Cloud (remote) | Terraform Cloud (remote) |
| Apply approval | UI click or auto-apply | Local terminal confirmation |
| Best for | Teams, GitOps, PRs | Migration, troubleshooting, quick iteration |
| Setup | Connect GitHub OAuth once | `terraform login` + `cloud {}` block |
| Speculative plans | Yes — on PRs automatically | Yes — `terraform plan` streams output locally |

Both modes store state in Terraform Cloud. The difference is only in *how a run is triggered*.

---

## Concept: Execution Modes

| Mode | Where code runs | When to use |
|------|----------------|------------|
| **Remote** (default) | Terraform Cloud workers | Standard teams, free tier |
| **Local** | Your laptop — state stored in Cloud | Legacy tooling, air-gapped debugging |
| **Agent** | Self-hosted agent in your network | Private cloud resources, no internet egress |

For this lab you will use **Remote** mode (the default).

---

## Part A — Create a Terraform Cloud Account and Organization

### Step A1 — Sign up

1. Go to [https://app.terraform.io/signup/account](https://app.terraform.io/signup/account)
2. Fill in your email address, username, and password
3. Confirm your email
4. Log in at [https://app.terraform.io](https://app.terraform.io)

> The Free plan supports up to 500 resources across unlimited workspaces. No credit card required.

### Step A2 — Create an organization

1. After first login you are prompted to **Create a new organization**
2. Fill in:
   - **Organization name:** `robochef-training`
   - **Email:** your email address
3. Click **Create organization**

You now land on the organization dashboard. Note the URL:
```
https://app.terraform.io/app/robochef-training
```

---

## Part B — Create a GitHub Repo with a Simple Terraform Config

### Step B1 — Create the repo

1. Go to [https://github.com/new](https://github.com/new)
2. Repository name: `tf-cloud-059-demo`
3. Set visibility to **Public** (required for the free VCS integration)
4. Check **Add a README file** so the repo is initialized
5. Click **Create repository**

### Step B2 — Create `versions.tf`

In GitHub, click **Add file → Create new file**, name it `versions.tf`, paste:

```hcl
terraform {
  required_version = ">= 1.3"

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
```

Commit directly to `main`.

### Step B3 — Create `variables.tf`

```hcl
variable "pet_length" {
  description = "Number of words in the generated pet name"
  type        = number
  default     = 2
}

variable "owner" {
  description = "Owner tag written into the output file"
  type        = string
  default     = "saravanans"
}
```

### Step B4 — Create `main.tf`

```hcl
resource "random_pet" "name" {
  length    = var.pet_length
  separator = "-"
}

resource "local_file" "pet_record" {
  filename = "/tmp/pet.txt"
  content  = <<-EOT
    # Generated by Terraform Cloud
    # Lab 059 — robochef.co demo
    pet_name = ${random_pet.name.id}
    owner    = ${var.owner}
    project  = robochef.co
  EOT
}
```

### Step B5 — Create `outputs.tf`

```hcl
output "pet_name" {
  description = "The randomly generated pet name"
  value       = random_pet.name.id
}

output "file_path" {
  description = "Path of the file written by local_file"
  value       = local_file.pet_record.filename
}

output "file_content" {
  description = "Content written to the file"
  value       = local_file.pet_record.content
}
```

After committing all four files your repo should look like:

```
tf-cloud-059-demo/
├── README.md
├── versions.tf
├── variables.tf
├── main.tf
└── outputs.tf
```

> **Note on `local_file` in remote runs:** Terraform Cloud remote workers write `/tmp/pet.txt` to the ephemeral worker container filesystem. The file is not visible on your laptop, but Terraform still tracks it in state. This is intentional for the demo — it proves the run happened remotely and the state was captured.

---

## Part C — Connect GitHub to Terraform Cloud

### Step C1 — Add the VCS provider

1. In Terraform Cloud, go to **Organization Settings** (gear icon, top-right)
2. In the left sidebar: **VCS Providers**
3. Click **Add a VCS Provider**
4. Choose **GitHub.com**

### Step C2 — Register the OAuth application

Terraform Cloud shows two values you need to paste into GitHub:

| Field | Value shown by Terraform Cloud |
|-------|-------------------------------|
| Homepage URL | `https://app.terraform.io` |
| Authorization callback URL | `https://app.terraform.io/auth/github/callback` |

1. Click the **Register GitHub OAuth Application** link — it opens GitHub's OAuth App page
2. Fill in the fields using the values above
3. Click **Register application**
4. GitHub shows you a **Client ID** and lets you generate a **Client Secret**
5. Copy both values back into Terraform Cloud
6. Click **Connect and continue**

### Step C3 — Authorize the OAuth app

GitHub shows an authorization screen listing what Terraform Cloud will access:
- Read access to code and metadata in your repositories
- Read access to organization membership (if applicable)

Click **Authorize** (your GitHub username).

You are redirected back to Terraform Cloud. The VCS provider now shows:

```
GitHub.com
Status: Connected
OAuth Token: present
```

Terraform Cloud now has read access to your GitHub repositories. It never writes to GitHub on its own.

---

## Part D — Create a VCS-Driven Workspace

### Step D1 — New workspace

1. Click **New Workspace** (top-right of the organization dashboard)
2. Select **Version Control Workflow**

### Step D2 — Connect the repository

1. Under **Connect to a version control provider**, choose **GitHub.com** (the one you just connected)
2. A list of your GitHub repositories appears
3. Find and click **tf-cloud-059-demo**

### Step D3 — Configure the workspace

| Setting | Value |
|---------|-------|
| Workspace Name | `tf-cloud-059-demo` |
| Terraform Working Directory | *(leave blank — root of repo)* |
| VCS Branch | `main` |
| Auto Apply | *(leave unchecked for now — you will manually approve)* |
| Terraform Version | `~> 1.3` or the latest 1.x shown |

4. Click **Create workspace**

You land on the workspace overview. Terraform Cloud immediately queues a first plan.

---

## Part E — Configure Variables

Before approving the plan, add the Terraform variable for `owner`.

1. In the workspace, click **Variables** (left sidebar)
2. Under **Terraform Variables**, click **Add variable**
3. Fill in:

| Field | Value |
|-------|-------|
| Key | `owner` |
| Value | `saravanans` |
| Category | Terraform variable |
| Sensitive | No |
| Description | Owner tag for the output file |

4. Click **Save variable**

> No environment variables are needed for this demo because `hashicorp/random` and `hashicorp/local` require no cloud credentials.

---

## Part F — Trigger a Run and Review Output

### Step F1 — Trigger via UI

1. Click **Actions → Start new plan** (or the run is already queued from workspace creation)
2. Add a reason: `Lab 059 initial plan`
3. Click **Start plan**

### Step F2 — Review the plan output

The run page streams live output. The **Plan** phase output looks like:

```
Terraform v1.7.5
on linux_amd64
Initializing plugins and modules...

Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # local_file.pet_record will be created
  + resource "local_file" "pet_record" {
      + content              = (known after apply)
      + content_base64sha256 = (known after apply)
      + content_base64sha512 = (known after apply)
      + content_md5          = (known after apply)
      + content_sha1         = (known after apply)
      + content_sha256       = (known after apply)
      + content_sha512       = (known after apply)
      + directory_permission = "0777"
      + file_permission      = "0777"
      + filename             = "/tmp/pet.txt"
      + id                   = (known after apply)
    }

  # random_pet.name will be created
  + resource "random_pet" "name" {
      + id        = (known after apply)
      + length    = 2
      + separator = "-"
    }

Plan: 2 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + file_content = (known after apply)
  + file_path    = "/tmp/pet.txt"
  + pet_name     = (known after apply)
```

### Step F3 — Cost estimation

On the free/open-source plan, cost estimation is skipped:

```
Cost estimation skipped — no supported resources found.
```

### Step F4 — Confirm and apply

1. Scroll down to the **Apply** section
2. Type `yes` in the confirmation box (or click **Confirm & Apply**)

The **Apply** phase output:

```
random_pet.name: Creating...
random_pet.name: Creation complete after 0s [id=happy-flamingo]
local_file.pet_record: Creating...
local_file.pet_record: Creation complete after 0s [id=3f4a7d2e1b...]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

file_content = <<EOT
# Generated by Terraform Cloud
# Lab 059 — robochef.co demo
pet_name = happy-flamingo
owner    = saravanans
project  = robochef.co

EOT
file_path = "/tmp/pet.txt"
pet_name  = "happy-flamingo"
```

The run status changes to **Applied**.

---

## Part G — Inspect State in the UI

### Step G1 — Open the States tab

1. In the workspace left sidebar, click **States**
2. You see a list of state versions:

```
Version   Created             Resources   Triggered by
─────────────────────────────────────────────────────
#1        2026-05-21 10:14    2           UI (manual run)
```

3. Click on **#1** to open the state snapshot

### Step G2 — Browse state resources

The UI shows the equivalent of `terraform state list`:

```
local_file.pet_record
random_pet.name
```

Click on **random_pet.name** to see the equivalent of `terraform state show random_pet.name`:

```json
{
  "id": "happy-flamingo",
  "length": 2,
  "separator": "-",
  "keepers": null,
  "prefix": null
}
```

> There is **no `terraform.tfstate` file on your laptop**. State is stored exclusively in Terraform Cloud, versioned, and locked during runs to prevent concurrent modifications.

### Step G3 — Trigger a second run by pushing a commit

Edit `variables.tf` in GitHub — change `pet_length` default from `2` to `3`:

```hcl
variable "pet_length" {
  description = "Number of words in the generated pet name"
  type        = number
  default     = 3        # changed from 2
}
```

Commit to `main`. Within seconds Terraform Cloud detects the push and queues a new plan automatically. This is the VCS-driven workflow in action: **git push = plan trigger**.

The new plan shows:

```
  # random_pet.name must be replaced
-/+ resource "random_pet" "name" {
      ~ id        = "happy-flamingo" -> (known after apply) # forces replacement
      ~ length    = 2 -> 3           # forces replacement
        separator = "-"
    }

  # local_file.pet_record must be replaced
-/+ resource "local_file" "pet_record" {
      ~ content  = ... -> (known after apply) # forces replacement
        filename = "/tmp/pet.txt"
    }

Plan: 2 to add, 0 to change, 2 to destroy.
```

Confirm and apply. The **States** tab now shows version **#2**.

---

## Part H — CLI-Driven Mode (Alternative Workflow)

This part shows how to trigger runs from your local terminal instead of the GitHub push or UI. The plan and apply still run remotely on Terraform Cloud — only the trigger is local.

### Step H1 — Install Terraform CLI

If not already installed:

```bash
# Ubuntu / Debian
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | \
  sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install terraform

terraform version
# Terraform v1.7.5
```

### Step H2 — Log in to Terraform Cloud

```bash
terraform login
```

Expected output:

```
Terraform will request an API token for app.terraform.io using your browser.

If login is successful, Terraform will store the token in plain text in
the following file for use by subsequent commands:
    /home/saravanans/.terraform.d/credentials.tfrc.json

Do you want to proceed?
  Only 'yes' will be accepted to confirm.

  Enter a value: yes
```

A browser window opens. Log in with your Terraform Cloud credentials. Terraform Cloud generates a personal API token and displays it. Paste it back into the terminal if not auto-filled, or click **Create API token** and copy.

The CLI confirms:

```
Retrieved token for user saravanans

─────────────────────────────────────────────────────────

                                          -
                                          -----                           -
                                          ---------                      --
                                          ---------  -                -----
                                           ---------  ------        -------
                                             -------  ---------  ----------
                                                ----  ---------- ----------
                                                  --  ---------- ----------
   Welcome to Terraform Cloud!                     -  ---------- -------
                                                      ---  ----- ---
   Documentation: terraform.io/docs/cloud             --------   -
                                                          ----------
                                                          ----------
                                                           ---------
                                                               ----

   New to TFC? Follow these steps to instantly apply an example configuration:

   $ git clone https://github.com/hashicorp/tfc-getting-started.git
   $ cd tfc-getting-started
   $ scripts/setup.sh
```

The token is stored at:
```
~/.terraform.d/credentials.tfrc.json
```

### Step H3 — Clone the repo and add the `cloud` block

```bash
git clone https://github.com/<your-username>/tf-cloud-059-demo.git
cd tf-cloud-059-demo
```

Open `versions.tf` and add a `cloud {}` block inside the `terraform {}` block:

```hcl
terraform {
  required_version = ">= 1.3"

  cloud {
    organization = "robochef-training"
    workspaces {
      name = "tf-cloud-059-demo"
    }
  }

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
```

> The `cloud {}` block replaces any `backend {}` block. You cannot have both.

### Step H4 — Init

```bash
terraform init
```

Expected:

```
Initializing Terraform Cloud...

Initializing provider plugins...
- Reusing previous version of hashicorp/random from the dependency lock file
- Reusing previous version of hashicorp/local from the dependency lock file
- Using previously-installed hashicorp/random v3.7.2
- Using previously-installed hashicorp/local v2.5.3

Terraform Cloud has been successfully initialized!

You may now begin working with Terraform Cloud. Try running "terraform plan"
to see any changes that are required for your infrastructure.

If you ever set or change modules or Terraform settings, run "terraform
init" again to reinitialize your working directory.
```

### Step H5 — Plan (runs remotely, output streamed locally)

```bash
terraform plan
```

Expected:

```
Running plan in Terraform Cloud. Output will stream here. Pressing Ctrl-C
will stop streaming the logs, but will not stop the run from completing.

Preparing the remote plan...

To view this run in a browser, visit:
https://app.terraform.io/app/robochef-training/tf-cloud-059-demo/runs/run-AbCdEfGhIjKl

Waiting for the plan to start...

Terraform v1.7.5
on linux_amd64
  + provider registry.terraform.io/hashicorp/local v2.5.3
  + provider registry.terraform.io/hashicorp/random v3.7.2

Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  ~ update in-place

Terraform will perform the following actions:

  # random_pet.name is up-to-date
  # local_file.pet_record is up-to-date

No changes. Your infrastructure matches the configuration.
```

### Step H6 — Apply (runs remotely)

Make a change — edit `variables.tf`, set default `pet_length` back to `2` — then:

```bash
terraform apply
```

Expected:

```
Running apply in Terraform Cloud. Output will stream here. Pressing Ctrl-C
will stop streaming the logs, but will not stop the run from completing.

Preparing the remote apply...

To view this run in a browser, visit:
https://app.terraform.io/app/robochef-training/tf-cloud-059-demo/runs/run-MnOpQrStUvWx

Waiting for the apply to start...

Terraform v1.7.5
on linux_amd64

random_pet.name: Destroying... [id=elegant-witty-flamingo]
random_pet.name: Destruction complete after 0s
local_file.pet_record: Destroying... [id=...]
local_file.pet_record: Destruction complete after 0s
random_pet.name: Creating...
random_pet.name: Creation complete after 0s [id=busy-lemur]
local_file.pet_record: Creating...
local_file.pet_record: Creation complete after 0s [id=...]

Apply complete! Resources: 2 added, 0 changed, 2 destroyed.

Outputs:

file_content = <<EOT
# Generated by Terraform Cloud
# Lab 059 — robochef.co demo
pet_name = busy-lemur
owner    = saravanans
project  = robochef.co

EOT
file_path = "/tmp/pet.txt"
pet_name  = "busy-lemur"
```

> The apply ran on a Terraform Cloud worker. The URL shown lets you inspect the same run in the UI. Your laptop has no `terraform.tfstate` — the state was saved to Terraform Cloud automatically.

---

## Part I — Cleanup

### Option 1 — Destroy from the UI (recommended)

1. In the workspace, click **Settings** (left sidebar)
2. Click **Destruction and Deletion**
3. Under **Destroy Infrastructure**, click **Queue destroy plan**
4. Type the workspace name `tf-cloud-059-demo` to confirm
5. Click **Queue destroy plan**

The destroy run appears in the **Runs** tab. Confirm and apply as normal:

```
random_pet.name: Destroying... [id=busy-lemur]
local_file.pet_record: Destroying... [id=...]
random_pet.name: Destruction complete after 0s
local_file.pet_record: Destruction complete after 0s

Destroy complete! Resources: 2 destroyed.
```

### Option 2 — Destroy from the CLI

```bash
terraform destroy
```

```
Running destroy in Terraform Cloud. Output will stream here.

random_pet.name: Destroying...
local_file.pet_record: Destroying...
random_pet.name: Destruction complete after 0s
local_file.pet_record: Destruction complete after 0s

Destroy complete! Resources: 2 destroyed.
```

### Delete the workspace

After infrastructure is destroyed:

1. Workspace → **Settings → Destruction and Deletion**
2. Scroll to **Delete Workspace**
3. Type the workspace name and click **Delete workspace**

> No `rm -rf .terraform` is needed. Terraform Cloud runs remotely — there is no local `.terraform` directory containing provider binaries to clean up.

---

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| **Organization** | Top-level namespace in Terraform Cloud — groups workspaces, teams, and billing |
| **Workspace** | Manages one root module's state and run history; maps to one environment |
| **Run** | A Plan + Apply lifecycle — triggered by VCS push, UI action, or CLI command |
| **State** | Versioned `terraform.tfstate` stored and locked by Terraform Cloud — no local file |
| **VCS Workflow** | GitHub push → automatic plan queued; team reviews and approves in the UI |
| **Remote Execution** | Plan and apply run on Terraform Cloud workers, not on the local machine |
| **`terraform login`** | Authenticates the local CLI to Terraform Cloud; token stored in `~/.terraform.d/credentials.tfrc.json` |
| **`cloud {}` block** | Replaces `backend {}` in `versions.tf`; points the CLI at an org + workspace |

---

## Comparison: Local State vs Terraform Cloud

| Concern | Local (open-source) | Terraform Cloud |
|---------|--------------------|-----------------| 
| State file location | `./terraform.tfstate` on disk | Terraform Cloud — versioned, encrypted |
| State locking | None (or DynamoDB if using S3) | Built-in — no extra setup |
| Run location | Developer's laptop | Terraform Cloud workers |
| Team access | Share state manually | All teammates see runs + state in UI |
| Audit trail | None | Full history of every run, who approved, outputs |
| Secrets in plan | Visible in terminal | Masked in UI for sensitive variables |
| Setup cost | Zero | Free tier: unlimited workspaces, 500 resources |

---

## Common Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `Error: Invalid credentials` | Not logged in | Run `terraform login` |
| `Organization not found` | Org name typo in `cloud {}` block | Check organization name at app.terraform.io |
| `Workspace ... already exists` | Workspace created earlier | Re-use existing workspace or delete and recreate |
| `Error loading state: state is locked` | Another run is in progress | Wait for current run to complete |
| `No VCS connection` | OAuth not set up | Repeat Part C |
| Plan runs but local_file shows no file | Expected — file is on the remote worker | Check outputs for content instead |

---

## Concept Summary

```
Terraform Cloud hierarchy:
  Organization → Workspace → Run → State

VCS-driven workflow:
  git push to GitHub → Terraform Cloud detects change → queues Plan
  → team reviews in UI → Confirm → Apply runs remotely → State saved

CLI-driven workflow:
  terraform login → stores token in ~/.terraform.d/credentials.tfrc.json
  Add cloud {} block to versions.tf with org + workspace name
  terraform init  → syncs local dir with Terraform Cloud workspace
  terraform plan  → plan runs on Cloud worker, output streamed locally
  terraform apply → apply runs on Cloud worker, state saved in Cloud

No local state:
  terraform.tfstate lives in Terraform Cloud only
  versioned, locked, encrypted — no S3 bucket or DynamoDB table needed

Execution mode (default = Remote):
  Remote → plan + apply on Cloud workers
  Local  → plan + apply on laptop, state in Cloud
  Agent  → plan + apply on your self-hosted agent, state in Cloud

No rm -rf .terraform needed:
  Provider binaries run on the Cloud worker, not on your laptop
  Local .terraform/ only contains the cloud backend plugin (~small)

Free tier:
  Up to 500 resources across unlimited workspaces
  No credit card required
  hashicorp/random + hashicorp/local → zero cloud cost, zero credentials
```
