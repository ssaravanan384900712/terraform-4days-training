# 001 — Install Terraform & Your First Resource (Live Demo)

**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~15 minutes

---

## Concept

This is a walk-through of installing Terraform from scratch on a fresh Ubuntu machine and creating your very first resource — a local file. No cloud account needed. By the end you will understand:

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   Download Binary → Write HCL → init → plan → apply        │
│        │                │         │       │       │         │
│        ▼                ▼         ▼       ▼       ▼         │
│   /usr/local/bin/   main.tf   .terraform  Preview  Create   │
│   terraform                   directory   changes  resource │
│                                                             │
│   Then: idempotency demo → drift demo → destroy             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Part 1 — Install Terraform (Manual Binary Method)

### Step 1 — Download the Terraform zip

```bash
wget https://releases.hashicorp.com/terraform/1.9.5/terraform_1.9.5_linux_amd64.zip
```

**Expected output:**

```
--2026-05-18 11:16:21--  https://releases.hashicorp.com/terraform/1.9.5/terraform_1.9.5_linux_amd64.zip
Resolving releases.hashicorp.com (releases.hashicorp.com)... 108.159.61.93, ...
Connecting to releases.hashicorp.com|108.159.61.93|:443... connected.
HTTP request sent, awaiting response... 200 OK
Length: 27040662 (26M) [application/zip]
Saving to: 'terraform_1.9.5_linux_amd64.zip'

terraform_1.9.5_linux_amd64.zip 100%[=========================>]  25.79M   228 MB/s   in 0.1s

2026-05-18 11:16:21 (228 MB/s) - 'terraform_1.9.5_linux_amd64.zip' saved [27040662/27040662]
```

### Step 2 — Install unzip (if not already installed)

```bash
sudo apt update && sudo apt install unzip -y
```

> **Common mistake:** Running `apt install` without `sudo` gives "Permission denied". Always use `sudo` for system packages.

### Step 3 — Unzip the binary

```bash
unzip terraform_1.9.5_linux_amd64.zip
```

```
Archive:  terraform_1.9.5_linux_amd64.zip
  inflating: LICENSE.txt
  inflating: terraform
```

### Step 4 — Move to system PATH

```bash
sudo mv terraform /usr/local/bin/
```

### Step 5 — Verify

```bash
terraform version
```

```
Terraform v1.9.5
on linux_amd64

Your version of Terraform is out of date! The latest version
is 1.15.3. You can update by downloading from https://www.terraform.io/downloads.html
```

> **Note:** The "out of date" warning is fine — v1.9.5 works perfectly for this training. Terraform is backwards-compatible across minor versions.

---

## Part 2 — Create Your Workspace

### Step 6 — Create a working directory

```bash
mkdir -p ~/tf_works/tf_demo
cd ~/tf_works/tf_demo
```

### Step 7 — Verify it's empty

```bash
ls
```

```
(empty)
```

```bash
ls -a
```

```
.  ..
```

> Only `.` (current dir) and `..` (parent dir). Completely empty.

---

## Part 3 — Write Your First Terraform File

### Step 8 — Create main.tf

```bash
nano main.tf
```

Type (or paste) this content:

```hcl
resource "local_file" "demofile" {
  content  = "Hello Folks of MassMutual"
  filename = "/tmp/demofile.txt"
}
```

Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X`).

### Step 9 — Verify the file

```bash
cat main.tf
```

```hcl
resource "local_file" "demofile" {
  content  = "Hello Folks of MassMutual"
  filename = "/tmp/demofile.txt"
}
```

### What does this code mean?

```
resource "local_file" "demofile" {
  │         │          │
  │         │          └── Name: YOUR label for this resource (any name you choose)
  │         └── Type: local_file (creates a file on disk)
  └── Keyword: tells Terraform "manage this thing"

  content  = "Hello Folks of MassMutual"   ← What to write in the file
  filename = "/tmp/demofile.txt"            ← Where to create the file
}
```

### Step 10 — Verify the target file does NOT exist yet

```bash
ls "/tmp/demofile.txt"
```

```
ls: cannot access '/tmp/demofile.txt': No such file or directory
```

> Good — the file doesn't exist. Terraform will create it.

---

## Part 4 — terraform init

### Step 11 — Initialize the project

```bash
terraform init
```

**Expected output:**

```
Initializing the backend...
Initializing provider plugins...
- Finding latest version of hashicorp/local...
- Installing hashicorp/local v2.9.0...
- Installed hashicorp/local v2.9.0 (signed by HashiCorp)
Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
```

### What just happened?

Terraform read your `main.tf`, saw you used `local_file` (which comes from the `hashicorp/local` provider), and **downloaded that provider plugin** automatically.

### Step 12 — See what init created

```bash
ls
```

```
main.tf
```

Wait — where did the files go? They're hidden:

```bash
ls -a
```

```
.  ..  .terraform  .terraform.lock.hcl  main.tf
```

Two new things:
- `.terraform/` — directory containing downloaded provider binaries
- `.terraform.lock.hcl` — locks the exact provider version

### Step 13 — Explore .terraform directory

```bash
sudo apt install tree -y    # Install tree if needed
tree .terraform
```

```
.terraform
└── providers
    └── registry.terraform.io
        └── hashicorp
            └── local
                └── 2.9.0
                    └── linux_amd64
                        ├── LICENSE.txt
                        └── terraform-provider-local_v2.9.0_x5

6 directories, 2 files
```

> **This is the provider plugin binary.** Terraform downloaded it from registry.terraform.io. The `_x5` suffix means protocol version 5. This directory is like `node_modules/` — never commit it to git, `terraform init` recreates it.

---

## Part 5 — terraform plan

### Step 14 — Preview what Terraform will do

```bash
terraform plan
```

**Expected output:**

```
Terraform used the selected providers to generate the following execution plan.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # local_file.demofile will be created
  + resource "local_file" "demofile" {
      + content              = "Hello Folks of MassMutual"
      + content_base64sha256 = (known after apply)
      + content_base64sha512 = (known after apply)
      + content_md5          = (known after apply)
      + content_sha1         = (known after apply)
      + content_sha256       = (known after apply)
      + content_sha512       = (known after apply)
      + directory_permission = "0777"
      + file_permission      = "0777"
      + filename             = "/tmp/demofile.txt"
      + id                   = (known after apply)
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

### Reading the plan output

```
+ create                          ← The + symbol means CREATE (new resource)

+ content = "Hello Folks..."      ← + before each attribute = will be set
+ filename = "/tmp/demofile.txt"  ← Where the file will be created

(known after apply)               ← These values are computed AFTER creation
                                    (hashes, IDs — Terraform can't know them yet)

Plan: 1 to add, 0 to change, 0 to destroy.
       │              │                │
       │              │                └── Nothing to delete
       │              └── Nothing to modify
       └── 1 new resource will be created
```

> **Key takeaway:** `terraform plan` is READ-ONLY. It changed nothing. It's always safe to run. Run it 100 times — nothing happens to your infrastructure.

---

## Part 6 — terraform apply

### Step 15 — Execute the plan

```bash
terraform apply
```

Terraform shows the same plan, then asks for confirmation:

```
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes
```

Type `yes` and press Enter.

```
local_file.demofile: Creating...
local_file.demofile: Creation complete after 0s [id=4f10852c9416e55dd1f7cdef0edaa09f0d44922f]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

### Step 16 — Verify the file was created

```bash
ls "/tmp/demofile.txt"
```

```
/tmp/demofile.txt
```

```bash
cat "/tmp/demofile.txt"
```

```
Hello Folks of MassMutual
```

> It works! Terraform created the file with exactly the content we specified.

---

## Part 7 — Idempotency (Running Apply Again)

### Step 17 — Run apply a second time

```bash
terraform apply
```

**Expected output:**

```
local_file.demofile: Refreshing state... [id=4f10852c9416e55dd1f7cdef0edaa09f0d44922f]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration and found
no differences, so no changes are needed.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

### What happened?

```
Step 1: "Refreshing state..." — Terraform checked the REAL file on disk
Step 2: Compared real file vs your main.tf code
Step 3: They match! → "No changes needed"
Step 4: 0 added, 0 changed, 0 destroyed
```

> **This is IDEMPOTENCY** — the most important concept in IaC. Running the same code twice produces the same result. No duplicates. No errors. Terraform only acts when reality doesn't match your code.

---

## Part 8 — Drift Detection (Manual Change)

### Step 18 — Simulate "drift" by deleting the file manually

```bash
rm /tmp/demofile.txt
```

> Someone (or a script, or a reboot) deleted the file outside of Terraform. Terraform doesn't know yet.

### Step 19 — Run apply — Terraform detects and fixes the drift

```bash
terraform apply
```

**Expected output:**

```
local_file.demofile: Refreshing state... [id=4f10852c9416e55dd1f7cdef0edaa09f0d44922f]

Terraform used the selected providers to generate the following execution plan.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # local_file.demofile will be created
  + resource "local_file" "demofile" {
      + content              = "Hello Folks of MassMutual"
      + filename             = "/tmp/demofile.txt"
      ...
    }

Plan: 1 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Enter a value: yes

local_file.demofile: Creating...
local_file.demofile: Creation complete after 0s [id=4f10852c9416e55dd1f7cdef0edaa09f0d44922f]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

### What happened?

```
1. Terraform refreshed state → checked /tmp/demofile.txt → FILE MISSING!
2. State says file should exist, but reality says it doesn't → DRIFT detected
3. Terraform plans to re-create the file
4. You approve → file is restored
```

> **Drift detection** is automatic. Every `terraform plan` and `terraform apply` compares state vs reality. This is why Terraform is powerful — it self-heals.

```bash
cat "/tmp/demofile.txt"
```

```
Hello Folks of MassMutual
```

> File is back!

---

## Part 9 — terraform destroy

### Step 20 — Destroy all managed resources

```bash
terraform destroy
```

**Expected output:**

```
local_file.demofile: Refreshing state... [id=4f10852c9416e55dd1f7cdef0edaa09f0d44922f]

Terraform used the selected providers to generate the following execution plan.
Resource actions are indicated with the following symbols:
  - destroy

Terraform will perform the following actions:

  # local_file.demofile will be destroyed
  - resource "local_file" "demofile" {
      - content              = "Hello Folks of MassMutual" -> null
      - content_base64sha256 = "3fDVIb7EoR6us46HH3wQxyV79rOTiZtQ6I673ucUVb0=" -> null
      - content_md5          = "8ceca3f493a9c43ebeb25c45710f2783" -> null
      - content_sha1         = "4f10852c9416e55dd1f7cdef0edaa09f0d44922f" -> null
      - directory_permission = "0777" -> null
      - file_permission      = "0777" -> null
      - filename             = "/tmp/demofile.txt" -> null
      - id                   = "4f10852c9416e55dd1f7cdef0edaa09f0d44922f" -> null
    }

Plan: 0 to add, 0 to change, 1 to destroy.

Do you really want to destroy all resources?
  Terraform will destroy all your managed infrastructure, as shown above.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: yes

local_file.demofile: Destroying... [id=4f10852c9416e55dd1f7cdef0edaa09f0d44922f]
local_file.demofile: Destruction complete after 0s

Destroy complete! Resources: 1 destroyed.
```

### Reading the destroy output

```
- destroy                              ← The - symbol means DESTROY
- content = "Hello..." -> null         ← Every attribute goes to null (deleted)
- filename = "/tmp/demofile.txt" -> null

Plan: 0 to add, 0 to change, 1 to destroy.
                                  │
                                  └── 1 resource will be removed
```

---

## Summary — The Complete Lifecycle

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  1. Write main.tf      → Define what you want                      │
│  2. terraform init     → Download provider plugins                 │
│  3. terraform plan     → Preview (safe, read-only)                 │
│  4. terraform apply    → Create resources (type "yes")             │
│  5. terraform apply    → Run again → "No changes" (idempotent!)   │
│  6. Delete file manually → terraform apply → Recreates it (drift!) │
│  7. terraform destroy  → Clean up everything                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Plan Symbol Cheat Sheet

| Symbol | Meaning | Example |
|--------|---------|---------|
| `+` | **Create** | New resource | 
| `-` | **Destroy** | Remove resource |
| `~` | **Update** | Modify in-place |
| `-/+` | **Replace** | Destroy + recreate |
| `<=` | **Read** | Data source refresh |

### Files Created by Terraform

| File | Created By | Purpose |
|------|-----------|---------|
| `main.tf` | You | Your infrastructure code |
| `.terraform/` | `terraform init` | Downloaded provider binaries |
| `.terraform.lock.hcl` | `terraform init` | Locks provider versions |
| `terraform.tfstate` | `terraform apply` | Tracks what Terraform manages |

### Key Concepts Learned

| Concept | What It Means |
|---------|--------------|
| **Provider** | Plugin that talks to an API (local filesystem, AWS, etc.) |
| **Resource** | A thing Terraform manages (`local_file`, `aws_instance`, etc.) |
| **State** | Terraform's memory of what it created |
| **Idempotency** | Apply twice → same result, no duplicates |
| **Drift** | Reality changed outside Terraform — detected and fixed on next apply |

---

> **Next:** Proceed to the local provider exercises (Hands-On 1.2a) to practice with multiple resources, variables, and outputs.
