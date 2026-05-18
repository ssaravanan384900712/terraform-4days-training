# Hands-On 1.2a -- Learning Terraform with the Local Provider

This is your very first time writing Terraform code. We will start with the simplest possible provider -- the **local provider** -- which creates files on your own machine. No cloud account needed. No cost. No risk. By the end of this lab you will understand providers, resources, variables, outputs, state, and the full Terraform lifecycle.

---

## Concept

### What is a Provider?

Terraform by itself does not know how to create anything. It relies on **providers** -- plugins that translate your HCL configuration into API calls. Every cloud, service, or tool you want to manage needs a provider.

Think of it this way:

```
  You (write HCL)
       |
       v
  Terraform CLI  (reads your .tf files, builds a plan)
       |
       v
  Provider Plugin  (downloaded from the Terraform Registry)
       |
       v
  Target API / Filesystem / Service
```

For AWS, the provider talks to the AWS API. For the **local** provider, it talks to your local filesystem. The workflow is identical -- only the target changes.

### The Terraform Registry

All official and community providers live at **https://registry.terraform.io**. When you run `terraform init`, Terraform downloads the provider binary from the registry into your project.

| Term | Meaning |
|------|---------|
| **Source** | Registry address, e.g. `hashicorp/local` |
| **Version** | Semantic version, e.g. `~> 2.0` (any 2.x) |
| **Provider block** | Optional configuration for the provider |
| **Resource** | A single infrastructure object managed by a provider |

### Why Start with the Local Provider?

| Benefit | Explanation |
|---------|-------------|
| No account needed | Works entirely on your machine |
| Zero cost | No cloud charges |
| Instant feedback | Files appear in seconds |
| Same workflow | init, plan, apply, destroy -- identical to AWS |
| Safe to experiment | Worst case: you create a text file |

---

## Step-by-Step

### Exercise 1: Hello Terraform

#### Step 1: Create a project directory

Every Terraform project lives in its own directory. Create one now:

```bash
mkdir -p ~/terraform-labs/lab-local
cd ~/terraform-labs/lab-local
```

#### Step 2: Write your first configuration

Create a file named `main.tf`. This is the conventional name for the primary configuration file.

```hcl
# main.tf -- My very first Terraform configuration

# -------------------------------------------------------
# Terraform Settings Block
# This tells Terraform which version of itself is needed
# and which providers to download.
# -------------------------------------------------------
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    local = {
      source  = "hashicorp/local"   # Download from the Terraform Registry
      version = "~> 2.0"            # Any 2.x version
    }
  }
}

# -------------------------------------------------------
# Resource Block
# A resource is a single object Terraform manages.
# Format: resource "<PROVIDER>_<TYPE>" "<NAME>" { ... }
# -------------------------------------------------------
resource "local_file" "hello" {
  filename = "${path.module}/hello.txt"
  content  = "Hello, Terraform!\n"
}
```

Let us break down every piece:

| Line | Purpose |
|------|---------|
| `terraform { }` | Settings block -- required in every project |
| `required_version` | Minimum Terraform CLI version |
| `required_providers` | Which provider plugins to download |
| `source = "hashicorp/local"` | Registry address: namespace/provider |
| `version = "~> 2.0"` | Version constraint (any 2.x, not 3.x) |
| `resource "local_file" "hello"` | Create a resource of type `local_file` named `hello` |
| `filename` | Where on disk the file will be created |
| `content` | What goes inside the file |
| `${path.module}` | Built-in variable: the directory containing this .tf file |

#### Step 3: Initialize the project

```bash
terraform init
```

**Expected output:**
```
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/local versions matching "~> 2.0"...
- Installing hashicorp/local v2.5.1...
- Installed hashicorp/local v2.5.1 (signed by HashiCorp)

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!
```

What just happened?

| Created | Purpose |
|---------|---------|
| `.terraform/` directory | Stores downloaded provider binaries |
| `.terraform.lock.hcl` file | Records exact versions and checksums (commit this to Git) |

```bash
ls -la .terraform/providers/registry.terraform.io/hashicorp/local/
```

You will see the provider binary inside. Terraform downloaded it from the registry.

> **Tip:** You must run `terraform init` once in every new project directory, and again whenever you add or change providers.

#### Step 4: Preview what Terraform will do

```bash
terraform plan
```

**Expected output:**
```
Terraform used the selected providers to generate the following execution plan.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # local_file.hello will be created
  + resource "local_file" "hello" {
      + content              = "Hello, Terraform!\n"
      + content_base64sha256 = (known after apply)
      + content_base64sha512 = (known after apply)
      + content_md5          = (known after apply)
      + content_sha1         = (known after apply)
      + content_sha256       = (known after apply)
      + content_sha512       = (known after apply)
      + directory_permission = "0777"
      + file_permission      = "0777"
      + filename             = "./hello.txt"
      + id                   = (known after apply)
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

Reading the plan output:

| Symbol | Meaning |
|--------|---------|
| `+` | This attribute will be **created** |
| `(known after apply)` | Value is computed -- Terraform cannot know it until the resource exists |
| `Plan: 1 to add` | One resource will be created |

The plan is a **dry run**. Nothing has been created yet. This is your chance to review before making changes.

#### Step 5: Apply the configuration

```bash
terraform apply
```

Terraform shows the same plan and asks for confirmation:

```
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes
```

Type `yes` and press Enter.

**Expected output:**
```
local_file.hello: Creating...
local_file.hello: Creation complete after 0s [id=8f863f51b40023e509e7898af4b7b1a53e44d797]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

#### Step 6: Verify the file was created

```bash
cat hello.txt
```

**Expected output:**
```
Hello, Terraform!
```

Congratulations -- you just managed your first piece of infrastructure with Terraform.

#### Step 7: Inspect the state

```bash
terraform show
```

**Expected output:**
```
# local_file.hello:
resource "local_file" "hello" {
    content              = "Hello, Terraform!\n"
    content_base64sha256 = "abc123..."
    content_md5          = "def456..."
    content_sha1         = "8f863f51b40023e509e7898af4b7b1a53e44d797"
    content_sha256       = "..."
    content_sha512       = "..."
    directory_permission = "0777"
    file_permission      = "0777"
    filename             = "./hello.txt"
    id                   = "8f863f51b40023e509e7898af4b7b1a53e44d797"
}
```

Terraform now knows about this file. It stored every attribute in its **state file** (`terraform.tfstate`). This is how Terraform tracks what it has created.

---

### Exercise 2: Multiple Files

You can define as many resources as you need. Let us create three files at once.

#### Step 1: Replace the content of `main.tf`

```hcl
# main.tf -- Multiple local files

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

resource "local_file" "index" {
  filename = "${path.module}/website/index.html"
  content  = <<-EOF
    <!DOCTYPE html>
    <html>
      <head><title>My Site</title></head>
      <body><h1>Welcome</h1></body>
    </html>
  EOF
}

resource "local_file" "style" {
  filename = "${path.module}/website/style.css"
  content  = <<-EOF
    body {
      font-family: Arial, sans-serif;
      margin: 40px;
      background-color: #f5f5f5;
    }
    h1 { color: #333; }
  EOF
}

resource "local_file" "app" {
  filename = "${path.module}/website/app.js"
  content  = <<-EOF
    console.log("App loaded");
    document.addEventListener("DOMContentLoaded", function() {
      console.log("Ready");
    });
  EOF
}
```

> **Tip:** The `<<-EOF ... EOF` syntax is called a **heredoc**. It lets you write multi-line strings. The `-` in `<<-EOF` strips leading whitespace so your HCL stays indented neatly.

#### Step 2: Plan and apply

```bash
terraform plan
```

**Expected output:**
```
local_file.hello: Refreshing state... [id=8f863f51b40023e509e7898af4b7b1a53e44d797]

Terraform will perform the following actions:

  # local_file.hello will be destroyed
  # (because local_file.hello is not in configuration)
  - resource "local_file" "hello" { ... }

  # local_file.app will be created
  + resource "local_file" "app" { ... }

  # local_file.index will be created
  + resource "local_file" "index" { ... }

  # local_file.style will be created
  + resource "local_file" "style" { ... }

Plan: 3 to add, 0 to change, 1 to destroy.
```

Notice: Terraform will **destroy** `local_file.hello` because we removed it from the configuration. It will **create** three new files. This is declarative -- your code is the desired state.

```bash
terraform apply
```

Type `yes`. Then verify:

```bash
ls website/
```

**Expected output:**
```
app.js  index.html  style.css
```

```bash
cat website/index.html
```

**Expected output:**
```
<!DOCTYPE html>
<html>
  <head><title>My Site</title></head>
  <body><h1>Welcome</h1></body>
</html>
```

---

### Exercise 3: Using Variables

Hardcoding values makes configurations inflexible. Variables let you parameterize your code.

#### Step 1: Create `variables.tf`

```hcl
# variables.tf -- Input variables

variable "project_name" {
  description = "Name of the project (used in filenames)"
  type        = string
  default     = "myapp"
}

variable "content" {
  description = "Content to write into the config file"
  type        = string
  default     = "# Default configuration\napp_mode = development\n"
}
```

#### Step 2: Update `main.tf`

Replace the entire content of `main.tf`:

```hcl
# main.tf -- Using variables

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

resource "local_file" "config" {
  filename = "${path.module}/${var.project_name}-config.txt"
  content  = var.content
}
```

#### Step 3: Plan with default values

```bash
terraform plan
```

**Expected output (partial):**
```
  # local_file.config will be created
  + resource "local_file" "config" {
      + content              = "# Default configuration\napp_mode = development\n"
      + filename             = "./myapp-config.txt"
      ...
    }

Plan: 1 to add, 0 to change, 3 to destroy.
```

The three website files will be destroyed (they are no longer in the config), and one new file will be created using the **default** variable values.

#### Step 4: Override variables from the command line

```bash
terraform apply -var="project_name=webapp" -var='content=# Production\napp_mode = production\n'
```

Type `yes`. Then check:

```bash
cat webapp-config.txt
```

**Expected output:**
```
# Production
app_mode = production
```

#### Step 5: Use a terraform.tfvars file

Instead of passing `-var` every time, create a file that Terraform reads automatically:

```hcl
# terraform.tfvars

project_name = "billing-service"
content      = <<-EOF
  # Billing Service Config
  app_mode = staging
  log_level = debug
  max_retries = 3
EOF
```

```bash
terraform apply
```

Type `yes`. Terraform reads `terraform.tfvars` automatically.

```bash
cat billing-service-config.txt
```

**Expected output:**
```
# Billing Service Config
app_mode = staging
log_level = debug
max_retries = 3
```

> **Tip:** Variable precedence (lowest to highest): default value in `variables.tf` < `terraform.tfvars` < `*.auto.tfvars` < `-var` flag < `TF_VAR_` environment variable.

---

### Exercise 4: Outputs

Outputs let you extract values from your Terraform configuration. They are displayed after `apply` and can be queried later.

#### Step 1: Create `outputs.tf`

```hcl
# outputs.tf -- Output values

output "config_filename" {
  description = "Path to the generated config file"
  value       = local_file.config.filename
}

output "config_md5" {
  description = "MD5 hash of the config file content"
  value       = local_file.config.content_md5
}

output "project_name" {
  description = "The project name used"
  value       = var.project_name
}
```

#### Step 2: Apply and see outputs

```bash
terraform apply
```

**Expected output (at the end):**
```
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

config_filename = "./billing-service-config.txt"
config_md5      = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
project_name    = "billing-service"
```

#### Step 3: Query outputs later

```bash
terraform output
```

**Expected output:**
```
config_filename = "./billing-service-config.txt"
config_md5      = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
project_name    = "billing-service"
```

```bash
# Get a single output (raw, no quotes)
terraform output -raw config_filename
```

**Expected output:**
```
./billing-service-config.txt
```

> **Tip:** In real projects, outputs are how you pass information between Terraform modules or to other tools (CI/CD pipelines, scripts, etc.).

---

### Exercise 5: Update and Destroy

#### Step 1: Change the content

Edit `terraform.tfvars`:

```hcl
# terraform.tfvars

project_name = "billing-service"
content      = <<-EOF
  # Billing Service Config -- UPDATED
  app_mode = production
  log_level = warn
  max_retries = 5
  timeout = 30
EOF
```

#### Step 2: Plan the update

```bash
terraform plan
```

**Expected output:**
```
  # local_file.config will be updated in-place
  ~ resource "local_file" "config" {
      ~ content              = <<-EOT
          - # Billing Service Config
          - app_mode = staging
          - log_level = debug
          - max_retries = 3
          + # Billing Service Config -- UPDATED
          + app_mode = production
          + log_level = warn
          + max_retries = 5
          + timeout = 30
        EOT
      ~ content_md5          = "a1b2c3d4..." -> (known after apply)
        # (6 unchanged attributes hidden)
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

Notice the `~` symbol -- it means **update in-place**. The file will be modified, not destroyed and recreated.

| Plan Symbol | Meaning |
|-------------|---------|
| `+` | Create a new resource |
| `-` | Destroy an existing resource |
| `~` | Update a resource in-place |
| `-/+` | Destroy and recreate (replacement) |

#### Step 3: Apply the update

```bash
terraform apply
```

Type `yes`. Then verify:

```bash
cat billing-service-config.txt
```

**Expected output:**
```
# Billing Service Config -- UPDATED
app_mode = production
log_level = warn
max_retries = 5
timeout = 30
```

#### Step 4: Destroy everything

```bash
terraform destroy
```

**Expected output:**
```
  # local_file.config will be destroyed
  - resource "local_file" "config" {
      - content              = <<-EOT
          # Billing Service Config -- UPDATED
          ...
        EOT
      - filename             = "./billing-service-config.txt"
      ...
    }

Plan: 0 to add, 0 to change, 1 to destroy.

Do you really want to destroy all resources?
  Enter a value: yes

local_file.config: Destroying... [id=...]
local_file.config: Destruction complete after 0s

Destroy complete! Resources: 1 destroyed.
```

The file is gone:

```bash
ls billing-service-config.txt
```

**Expected output:**
```
ls: cannot access 'billing-service-config.txt': No such file or directory
```

---

### Exercise 6: Sensitive Files

Some files contain secrets (passwords, API keys). Terraform has a special resource for that.

#### Step 1: Update `main.tf`

Add a second resource to `main.tf` (keep the existing `local_file.config`):

```hcl
# main.tf -- Regular and sensitive files

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

resource "local_file" "config" {
  filename = "${path.module}/${var.project_name}-config.txt"
  content  = var.content
}

resource "local_sensitive_file" "secret" {
  filename = "${path.module}/${var.project_name}-secret.env"
  content  = "DB_PASSWORD=SuperSecret123!\nAPI_KEY=sk-abc123def456\n"
}
```

#### Step 2: Plan and observe

```bash
terraform plan
```

**Expected output (partial):**
```
  # local_sensitive_file.secret will be created
  + resource "local_sensitive_file" "secret" {
      + content              = (sensitive value)
      + content_base64sha256 = (known after apply)
      + content_base64sha512 = (known after apply)
      + content_md5          = (known after apply)
      + content_sha1         = (known after apply)
      + content_sha256       = (known after apply)
      + content_sha512       = (known after apply)
      + directory_permission = "0700"
      + file_permission      = "0700"
      + filename             = "./billing-service-secret.env"
      + id                   = (known after apply)
    }
```

Notice two things:
1. The `content` shows `(sensitive value)` instead of the actual secret
2. The `file_permission` is `0700` (owner-only) instead of `0777`

This prevents secrets from leaking into plan output, logs, or CI/CD consoles.

#### Step 3: Apply and verify

```bash
terraform apply
```

Type `yes`.

```bash
ls -la billing-service-secret.env
```

**Expected output:**
```
-rwx------ 1 youruser yourgroup 45 ... billing-service-secret.env
```

The file has restricted permissions (only the owner can read it).

> **Warning:** The state file (`terraform.tfstate`) still contains the sensitive value in plain text. In production, always use a remote backend with encryption (S3 + DynamoDB, Terraform Cloud, etc.).

#### Step 4: Clean up

```bash
terraform destroy
```

Type `yes`.

---

### Exercise 7: Understanding State

State is how Terraform remembers what it has created. Let us explore it.

#### Step 1: Recreate resources

Make sure `main.tf` still has both `local_file.config` and `local_sensitive_file.secret`. Run:

```bash
terraform apply
```

Type `yes`.

#### Step 2: List resources in state

```bash
terraform state list
```

**Expected output:**
```
local_file.config
local_sensitive_file.secret
```

#### Step 3: Show details of a resource

```bash
terraform state show local_file.config
```

**Expected output:**
```
# local_file.config:
resource "local_file" "config" {
    content              = <<-EOT
        # Billing Service Config -- UPDATED
        app_mode = production
        log_level = warn
        max_retries = 5
        timeout = 30
    EOT
    content_base64sha256 = "..."
    content_md5          = "a1b2c3d4..."
    content_sha1         = "..."
    content_sha256       = "..."
    content_sha512       = "..."
    directory_permission = "0777"
    file_permission      = "0777"
    filename             = "./billing-service-config.txt"
    id                   = "..."
}
```

#### Step 4: Understand the state file

The state file is a JSON file:

```bash
cat terraform.tfstate | python3 -m json.tool | head -20
```

**Expected output (partial):**
```json
{
    "version": 4,
    "terraform_version": "1.9.5",
    "serial": 5,
    "lineage": "abc123-def456-...",
    "outputs": {
        "config_filename": {
            "value": "./billing-service-config.txt",
            "type": "string"
        },
        ...
    },
    "resources": [
        {
            "mode": "managed",
            "type": "local_file",
            "name": "config",
            ...
```

Key state concepts:

| Field | Purpose |
|-------|---------|
| `version` | State file format version |
| `serial` | Increments on every change (conflict detection) |
| `lineage` | Unique ID for this state -- prevents mixing states |
| `outputs` | Saved output values |
| `resources` | Every resource and its current attributes |

> **Warning:** Never manually edit `terraform.tfstate`. Use `terraform state` commands. A corrupted state file can cause Terraform to lose track of your infrastructure.

---

### Cleanup

```bash
terraform destroy
```

Type `yes`. All files are removed.

You can also safely delete the `.terraform/` directory to free disk space:

```bash
rm -rf .terraform/
```

If you run `terraform init` again later, it will re-download the providers.

> **Tip:** Always keep `.terraform.lock.hcl` in version control -- it ensures everyone on your team uses the same provider versions. Never commit `.terraform/` or `terraform.tfstate` to Git.

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| Provider | A plugin that talks to an API (local filesystem, AWS, etc.) |
| `terraform init` | Downloads providers, creates `.terraform/` |
| `terraform plan` | Dry run showing what will change |
| `terraform apply` | Executes the plan, creates/updates resources |
| `terraform destroy` | Removes all managed resources |
| Resource | A single infrastructure object (`local_file`, `local_sensitive_file`) |
| Variables | Parameterize your configuration (`variable`, `-var`, `terraform.tfvars`) |
| Outputs | Extract and display values from your infrastructure |
| State | JSON file tracking every resource Terraform manages |
| Plan symbols | `+` create, `~` update, `-` destroy, `-/+` replace |

You have now completed the full Terraform lifecycle without touching any cloud service. In the next lab, you will use the **random provider** to generate dynamic values -- building more skills before moving to AWS.
