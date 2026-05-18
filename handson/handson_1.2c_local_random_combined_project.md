# Hands-On 1.2c -- Mini Project: Config File Generator

This is a capstone lab that combines everything you learned in Labs 1.2a and 1.2b. You will build a **multi-environment config file generator** that creates configuration files and secrets for a fictional application across dev, staging, and prod environments. By the end, you will be confident with every core Terraform mechanic before touching AWS.

---

## Concept

### What We Are Building

A Terraform project that generates environment-specific configuration files and secret files for a multi-environment application:

```
  Input (variables.tf)             Processing (main.tf)           Output (Generated Files)
  +--------------------+           +--------------------+         +------------------------+
  | environments:      |           |                    |         | output/                |
  |   dev, staging,    | --------> | random_password    | ------> |   dev/                 |
  |   prod             |           |   (per env)        |         |     config.json        |
  |                    |           |                    |         |     secrets.env         |
  | app_name:          |           | random_id          |         |   staging/             |
  |   "myapp"          |           |   (deployment ID)  |         |     config.json        |
  |                    |           |                    |         |     secrets.env         |
  | base_port:         |           | templatefile()     |         |   prod/                |
  |   3000             |           |   (config.json)    |         |     config.json        |
  |                    |           |                    |         |     secrets.env         |
  | enable_debug:      |           | local_file         |         +------------------------+
  |   per environment  |           | local_sensitive_   |
  +--------------------+           |   file             |
                                   +--------------------+
```

### Skills You Will Practice

| Skill | How It Is Used |
|-------|----------------|
| Variables | Maps, strings, numbers, bools |
| `for_each` | One set of files per environment |
| `random_password` | Unique database password per env |
| `random_id` | Unique deployment identifier |
| `locals` | Computed intermediate values |
| `templatefile()` | Generate JSON from a template |
| `local_file` | Write config files |
| `local_sensitive_file` | Write secret files with restricted permissions |
| Outputs | Display paths and IDs |
| Variable validation | Enforce rules on inputs |

---

## Step-by-Step

### Step 1: Create the Project Structure

```bash
mkdir -p ~/terraform-labs/lab-config-generator/templates
cd ~/terraform-labs/lab-config-generator
```

Your final project structure will look like this:

```
lab-config-generator/
  variables.tf        # Input variable declarations
  main.tf             # Resources and data
  outputs.tf          # Output values
  terraform.tfvars    # Variable values
  templates/
    config.json.tpl   # Template for config files
```

---

### Step 2: Define Variables

Create `variables.tf`:

```hcl
# variables.tf -- Input variables for the config generator

variable "app_name" {
  description = "Application name (lowercase alphanumeric and hyphens only)"
  type        = string
  default     = "myapp"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.app_name))
    error_message = "app_name must start with a lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "base_port" {
  description = "Base port number. Each environment gets base_port + offset."
  type        = number
  default     = 3000

  validation {
    condition     = var.base_port >= 3000 && var.base_port <= 9000
    error_message = "base_port must be between 3000 and 9000."
  }
}

variable "environments" {
  description = "Map of environments with their settings"
  type = map(object({
    enable_debug  = bool
    log_level     = string
    replicas      = number
  }))
  default = {
    dev = {
      enable_debug = true
      log_level    = "debug"
      replicas     = 1
    }
    staging = {
      enable_debug = true
      log_level    = "info"
      replicas     = 2
    }
    prod = {
      enable_debug = false
      log_level    = "warn"
      replicas     = 3
    }
  }
}

variable "owner" {
  description = "Team or person who owns this application"
  type        = string
  default     = "platform-team"
}
```

Let us examine what each variable does:

| Variable | Type | Purpose |
|----------|------|---------|
| `app_name` | `string` | Application name, validated to be lowercase |
| `base_port` | `number` | Starting port, validated between 3000-9000 |
| `environments` | `map(object({...}))` | Complex type: a map where each value is an object with three fields |
| `owner` | `string` | Who owns the app (used in config metadata) |

> **Tip:** The `validation` blocks run before Terraform creates anything. They catch bad input early. This same pattern works with AWS variables -- you can validate AMI IDs, region names, CIDR blocks, etc.

#### Test the validations

```bash
terraform init
```

**Expected output:**
```
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/random versions matching "~> 3.0"...
- Finding hashicorp/local versions matching "~> 2.0"...
- Installing hashicorp/random v3.6.3...
- Installed hashicorp/random v3.6.3 (signed by HashiCorp)
- Installing hashicorp/local v2.5.1...
- Installed hashicorp/local v2.5.1 (signed by HashiCorp)

Terraform has been successfully initialized!
```

Wait -- we have not created `main.tf` yet. `terraform init` still works because it only needs the provider declarations. Let us test validation with a plan:

```bash
terraform plan -var="app_name=INVALID_NAME"
```

**Expected output:**
```
Error: Invalid value for variable

  on variables.tf line 4:
   4: variable "app_name" {

app_name must start with a lowercase letter and contain only lowercase
letters, numbers, and hyphens.
```

```bash
terraform plan -var="base_port=99999"
```

**Expected output:**
```
Error: Invalid value for variable

  on variables.tf line 12:
  12: variable "base_port" {

base_port must be between 3000 and 9000.
```

The validations work. Bad input is rejected before any resources are created.

---

### Step 3: Create the Template

Create `templates/config.json.tpl`:

```json
{
  "application": {
    "name": "${app_name}",
    "environment": "${environment}",
    "version": "1.0.0"
  },
  "server": {
    "port": ${port},
    "debug": ${debug},
    "log_level": "${log_level}"
  },
  "scaling": {
    "replicas": ${replicas}
  },
  "metadata": {
    "deployment_id": "${deployment_id}",
    "owner": "${owner}",
    "generated_by": "terraform",
    "generated_at": "${timestamp}"
  }
}
```

This is a **template file**. The `${...}` placeholders will be filled in by Terraform's `templatefile()` function. The template itself is not HCL -- it is plain text with interpolation markers.

---

### Step 4: Write the Main Configuration

Create `main.tf`:

```hcl
# main.tf -- Config file generator

terraform {
  required_version = ">= 1.5.0"

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

# -------------------------------------------------------
# Random Resources
# -------------------------------------------------------

# Generate a unique password for each environment
resource "random_password" "db_password" {
  for_each = var.environments

  length           = 20
  special          = true
  override_special = "!@#$%&*()-_=+[]{}|;:,.<>?"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# Generate a unique deployment ID
resource "random_id" "deployment" {
  byte_length = 6
}

# -------------------------------------------------------
# Local Values (Computed)
# -------------------------------------------------------

locals {
  # Build a computed config for each environment
  env_configs = {
    for env_name, env_settings in var.environments : env_name => {
      environment   = env_name
      app_name      = var.app_name
      port          = var.base_port + index(keys(var.environments), env_name)
      debug         = env_settings.enable_debug
      log_level     = env_settings.log_level
      replicas      = env_settings.replicas
      deployment_id = random_id.deployment.hex
      owner         = var.owner
      timestamp     = timestamp()
    }
  }
}

# -------------------------------------------------------
# Config Files (one per environment)
# -------------------------------------------------------

resource "local_file" "config" {
  for_each = var.environments

  filename = "${path.module}/output/${each.key}/config.json"
  content = templatefile("${path.module}/templates/config.json.tpl", {
    app_name      = var.app_name
    environment   = each.key
    port          = var.base_port + index(keys(var.environments), each.key)
    debug         = var.environments[each.key].enable_debug
    log_level     = var.environments[each.key].log_level
    replicas      = var.environments[each.key].replicas
    deployment_id = random_id.deployment.hex
    owner         = var.owner
    timestamp     = timestamp()
  })

  file_permission = "0644"
}

# -------------------------------------------------------
# Secret Files (one per environment, sensitive)
# -------------------------------------------------------

resource "local_sensitive_file" "secrets" {
  for_each = var.environments

  filename = "${path.module}/output/${each.key}/secrets.env"
  content  = <<-EOF
    # Secrets for ${var.app_name} -- ${each.key} environment
    # Generated by Terraform -- DO NOT EDIT MANUALLY
    DB_PASSWORD=${random_password.db_password[each.key].result}
    APP_SECRET_KEY=${random_id.deployment.hex}-${each.key}
    ENVIRONMENT=${each.key}
  EOF

  file_permission = "0600"
}
```

Let us break down the key patterns:

| Pattern | What It Does |
|---------|--------------|
| `random_password.db_password` with `for_each` | Creates one password per environment |
| `random_id.deployment` | Single shared deployment ID |
| `locals { env_configs = ... }` | A `for` expression builds a computed map |
| `index(keys(var.environments), env_name)` | Gets the numeric index of a key in the sorted map (0, 1, 2) for port offsets |
| `templatefile(path, vars)` | Renders a template with the given variables |
| `local_file.config` with `for_each` | Creates one config.json per environment |
| `local_sensitive_file.secrets` with `for_each` | Creates one secrets.env per environment with restricted permissions |
| `random_password.db_password[each.key]` | Accesses the specific password for this environment |

> **Tip:** `locals` are like computed variables. They are not inputs -- they are intermediate values calculated from other data. Use them to keep your resource blocks clean.

---

### Step 5: Define Outputs

Create `outputs.tf`:

```hcl
# outputs.tf -- Output values

output "deployment_id" {
  description = "Unique deployment identifier"
  value       = random_id.deployment.hex
}

output "config_files" {
  description = "Paths to generated config files"
  value       = { for env, file in local_file.config : env => file.filename }
}

output "secret_files" {
  description = "Paths to generated secret files"
  value       = { for env, file in local_sensitive_file.secrets : env => file.filename }
}

output "environment_ports" {
  description = "Port assignments per environment"
  value = {
    for env_name in keys(var.environments) :
    env_name => var.base_port + index(keys(var.environments), env_name)
  }
}

output "db_passwords" {
  description = "Database passwords per environment (sensitive)"
  value       = { for env, pw in random_password.db_password : env => pw.result }
  sensitive   = true
}
```

---

### Step 6: Create the tfvars File

Create `terraform.tfvars`:

```hcl
# terraform.tfvars -- Variable values for the config generator

app_name  = "order-service"
base_port = 5000
owner     = "backend-team"

environments = {
  dev = {
    enable_debug = true
    log_level    = "debug"
    replicas     = 1
  }
  staging = {
    enable_debug = true
    log_level    = "info"
    replicas     = 2
  }
  prod = {
    enable_debug = false
    log_level    = "warn"
    replicas     = 3
  }
}
```

---

### Step 7: Run It

#### Initialize

```bash
terraform init
```

**Expected output:**
```
Initializing the backend...

Initializing provider plugins...
- Reusing previous version of hashicorp/random from the dependency lock file
- Reusing previous version of hashicorp/local from the dependency lock file
- Using previously-installed hashicorp/random v3.6.3
- Using previously-installed hashicorp/local v2.5.1

Terraform has been successfully initialized!
```

#### Format and validate

```bash
terraform fmt
terraform validate
```

**Expected output:**
```
Success! The configuration is valid.
```

#### Plan

```bash
terraform plan
```

**Expected output:**
```
Terraform will perform the following actions:

  # local_file.config["dev"] will be created
  + resource "local_file" "config" {
      + content              = (known after apply)
      + file_permission      = "0644"
      + filename             = "./output/dev/config.json"
      + id                   = (known after apply)
      ...
    }

  # local_file.config["prod"] will be created
  + resource "local_file" "config" {
      + content              = (known after apply)
      + file_permission      = "0644"
      + filename             = "./output/prod/config.json"
      + id                   = (known after apply)
      ...
    }

  # local_file.config["staging"] will be created
  + resource "local_file" "config" {
      + content              = (known after apply)
      + file_permission      = "0644"
      + filename             = "./output/staging/config.json"
      + id                   = (known after apply)
      ...
    }

  # local_sensitive_file.secrets["dev"] will be created
  + resource "local_sensitive_file" "secrets" {
      + content              = (sensitive value)
      + file_permission      = "0600"
      + filename             = "./output/dev/secrets.env"
      + id                   = (known after apply)
      ...
    }

  # local_sensitive_file.secrets["prod"] will be created
  + resource "local_sensitive_file" "secrets" {
      + content              = (sensitive value)
      + file_permission      = "0600"
      + filename             = "./output/prod/secrets.env"
      + id                   = (known after apply)
      ...
    }

  # local_sensitive_file.secrets["staging"] will be created
  + resource "local_sensitive_file" "secrets" {
      + content              = (sensitive value)
      + file_permission      = "0600"
      + filename             = "./output/staging/secrets.env"
      + id                   = (known after apply)
      ...
    }

  # random_id.deployment will be created
  + resource "random_id" "deployment" {
      + b64_std = (known after apply)
      + b64_url = (known after apply)
      + byte_length = 6
      + dec     = (known after apply)
      + hex     = (known after apply)
      + id      = (known after apply)
    }

  # random_password.db_password["dev"] will be created
  + resource "random_password" "db_password" {
      + bcrypt_hash      = (sensitive value)
      + id               = (known after apply)
      + length           = 20
      + min_lower        = 2
      + min_numeric      = 2
      + min_special      = 2
      + min_upper        = 2
      + override_special = "!@#$%&*()-_=+[]{}|;:,.<>?"
      + result           = (sensitive value)
      + special          = true
      ...
    }

  # random_password.db_password["prod"] will be created
  + resource "random_password" "db_password" { ... }

  # random_password.db_password["staging"] will be created
  + resource "random_password" "db_password" { ... }

Plan: 10 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + config_files      = {
      + "dev"     = "./output/dev/config.json"
      + "prod"    = "./output/prod/config.json"
      + "staging" = "./output/staging/config.json"
    }
  + db_passwords      = (sensitive value)
  + deployment_id     = (known after apply)
  + environment_ports = {
      + "dev"     = 5000
      + "prod"    = 5002
      + "staging" = 5001
    }
  + secret_files      = {
      + "dev"     = "./output/dev/secrets.env"
      + "prod"    = "./output/prod/secrets.env"
      + "staging" = "./output/staging/secrets.env"
    }
```

10 resources will be created: 3 passwords + 1 deployment ID + 3 config files + 3 secret files.

#### Apply

```bash
terraform apply
```

Type `yes`.

**Expected output:**
```
random_id.deployment: Creating...
random_password.db_password["dev"]: Creating...
random_password.db_password["staging"]: Creating...
random_password.db_password["prod"]: Creating...
random_id.deployment: Creation complete after 0s [id=abc123def456]
random_password.db_password["dev"]: Creation complete after 0s [id=none]
random_password.db_password["staging"]: Creation complete after 0s [id=none]
random_password.db_password["prod"]: Creation complete after 0s [id=none]
local_file.config["dev"]: Creating...
local_file.config["staging"]: Creating...
local_file.config["prod"]: Creating...
local_sensitive_file.secrets["dev"]: Creating...
local_sensitive_file.secrets["staging"]: Creating...
local_sensitive_file.secrets["prod"]: Creating...
local_file.config["dev"]: Creation complete after 0s [id=...]
local_file.config["staging"]: Creation complete after 0s [id=...]
local_file.config["prod"]: Creation complete after 0s [id=...]
local_sensitive_file.secrets["dev"]: Creation complete after 0s [id=...]
local_sensitive_file.secrets["staging"]: Creation complete after 0s [id=...]
local_sensitive_file.secrets["prod"]: Creation complete after 0s [id=...]

Apply complete! Resources: 10 added, 0 changed, 0 destroyed.

Outputs:

config_files = {
  "dev"     = "./output/dev/config.json"
  "prod"    = "./output/prod/config.json"
  "staging" = "./output/staging/config.json"
}
db_passwords      = <sensitive>
deployment_id     = "a1b2c3d4e5f6"
environment_ports = {
  "dev"     = 5000
  "prod"    = 5002
  "staging" = 5001
}
secret_files = {
  "dev"     = "./output/dev/secrets.env"
  "prod"    = "./output/prod/secrets.env"
  "staging" = "./output/staging/secrets.env"
}
```

---

### Step 8: Inspect the Generated Files

#### View the directory structure

```bash
find output/ -type f | sort
```

**Expected output:**
```
output/dev/config.json
output/dev/secrets.env
output/prod/config.json
output/prod/secrets.env
output/staging/config.json
output/staging/secrets.env
```

#### Read a config file

```bash
cat output/dev/config.json
```

**Expected output:**
```json
{
  "application": {
    "name": "order-service",
    "environment": "dev",
    "version": "1.0.0"
  },
  "server": {
    "port": 5000,
    "debug": true,
    "log_level": "debug"
  },
  "scaling": {
    "replicas": 1
  },
  "metadata": {
    "deployment_id": "a1b2c3d4e5f6",
    "owner": "backend-team",
    "generated_by": "terraform",
    "generated_at": "2025-01-15T10:30:00Z"
  }
}
```

```bash
cat output/prod/config.json
```

**Expected output:**
```json
{
  "application": {
    "name": "order-service",
    "environment": "prod",
    "version": "1.0.0"
  },
  "server": {
    "port": 5002,
    "debug": false,
    "log_level": "warn"
  },
  "scaling": {
    "replicas": 3
  },
  "metadata": {
    "deployment_id": "a1b2c3d4e5f6",
    "owner": "backend-team",
    "generated_by": "terraform",
    "generated_at": "2025-01-15T10:30:00Z"
  }
}
```

Notice: dev has `debug: true`, port 5000, 1 replica. Prod has `debug: false`, port 5002, 3 replicas. Same template, different values.

#### Check file permissions on secrets

```bash
ls -la output/dev/secrets.env
```

**Expected output:**
```
-rw------- 1 youruser yourgroup 156 ... output/dev/secrets.env
```

Owner-only read/write. The sensitive file resource automatically restricts permissions.

```bash
cat output/dev/secrets.env
```

**Expected output:**
```
# Secrets for order-service -- dev environment
# Generated by Terraform -- DO NOT EDIT MANUALLY
DB_PASSWORD=xY1@zW2#qR3$tU4%vB5^
APP_SECRET_KEY=a1b2c3d4e5f6-dev
ENVIRONMENT=dev
```

Each environment has a unique password.

#### Query outputs

```bash
terraform output deployment_id
terraform output environment_ports
terraform output config_files
terraform output db_passwords
```

---

### Step 9: Modify and Update

Let us add a new environment and change the base port. This demonstrates incremental updates.

#### Add a QA environment

Edit `terraform.tfvars`:

```hcl
# terraform.tfvars -- Updated with QA environment

app_name  = "order-service"
base_port = 6000
owner     = "backend-team"

environments = {
  dev = {
    enable_debug = true
    log_level    = "debug"
    replicas     = 1
  }
  qa = {
    enable_debug = true
    log_level    = "info"
    replicas     = 2
  }
  staging = {
    enable_debug = false
    log_level    = "info"
    replicas     = 2
  }
  prod = {
    enable_debug = false
    log_level    = "warn"
    replicas     = 3
  }
}
```

Changes made:
1. Added `qa` environment
2. Changed `base_port` from `5000` to `6000`
3. Changed staging `enable_debug` from `true` to `false`

#### Plan the changes

```bash
terraform plan
```

**Expected output (summarized):**
```
  # local_file.config["dev"] will be updated in-place
  ~ resource "local_file" "config" {
      ~ content = ...  (port changes from 5000 to 6000)
      ...
    }

  # local_file.config["qa"] will be created
  + resource "local_file" "config" {
      + filename = "./output/qa/config.json"
      ...
    }

  # local_file.config["staging"] will be updated in-place
  ~ resource "local_file" "config" {
      ~ content = ...  (port changes, debug changes)
      ...
    }

  # local_file.config["prod"] will be updated in-place
  ~ resource "local_file" "config" {
      ~ content = ...  (port changes)
      ...
    }

  # local_sensitive_file.secrets["qa"] will be created
  + resource "local_sensitive_file" "secrets" { ... }

  # random_password.db_password["qa"] will be created
  + resource "random_password" "db_password" { ... }

Plan: 3 to add, 6 to change, 0 to destroy.
```

Key observations:
- **3 to add**: QA config, QA secrets, QA password (new environment)
- **6 to change**: The existing config and secret files for dev, staging, and prod update because the port changed
- **0 to destroy**: Nothing is removed. The existing dev, staging, and prod environments persist.

This is the power of `for_each` -- adding a map entry only creates new resources. It does not affect existing ones (except when shared values like `base_port` change).

#### Apply

```bash
terraform apply
```

Type `yes`.

#### Verify the new QA environment

```bash
cat output/qa/config.json
```

**Expected output:**
```json
{
  "application": {
    "name": "order-service",
    "environment": "qa",
    "version": "1.0.0"
  },
  "server": {
    "port": 6001,
    "debug": true,
    "log_level": "info"
  },
  "scaling": {
    "replicas": 2
  },
  "metadata": {
    "deployment_id": "a1b2c3d4e5f6",
    "owner": "backend-team",
    "generated_by": "terraform",
    "generated_at": "2025-01-15T10:35:00Z"
  }
}
```

#### Verify updated ports

```bash
terraform output environment_ports
```

**Expected output:**
```
{
  "dev"     = 6000
  "prod"    = 6002
  "qa"      = 6001
  "staging" = 6003
}
```

All ports shifted because `base_port` changed from 5000 to 6000.

#### Check full state

```bash
terraform state list
```

**Expected output:**
```
local_file.config["dev"]
local_file.config["prod"]
local_file.config["qa"]
local_file.config["staging"]
local_sensitive_file.secrets["dev"]
local_sensitive_file.secrets["prod"]
local_sensitive_file.secrets["qa"]
local_sensitive_file.secrets["staging"]
random_id.deployment
random_password.db_password["dev"]
random_password.db_password["prod"]
random_password.db_password["qa"]
random_password.db_password["staging"]
```

13 resources managed by Terraform, all from a compact configuration.

---

### Step 10: Destroy and Clean Up

```bash
terraform destroy
```

**Expected output:**
```
  # local_file.config["dev"] will be destroyed
  - resource "local_file" "config" { ... }

  # local_file.config["prod"] will be destroyed
  - resource "local_file" "config" { ... }

  # local_file.config["qa"] will be destroyed
  - resource "local_file" "config" { ... }

  # local_file.config["staging"] will be destroyed
  - resource "local_file" "config" { ... }

  # local_sensitive_file.secrets["dev"] will be destroyed
  - resource "local_sensitive_file" "secrets" { ... }

  ...

Plan: 0 to add, 0 to change, 13 to destroy.

Do you really want to destroy all resources?
  Enter a value: yes

local_file.config["dev"]: Destroying...
local_file.config["prod"]: Destroying...
local_file.config["qa"]: Destroying...
local_file.config["staging"]: Destroying...
local_sensitive_file.secrets["dev"]: Destroying...
local_sensitive_file.secrets["staging"]: Destroying...
local_sensitive_file.secrets["prod"]: Destroying...
local_sensitive_file.secrets["qa"]: Destroying...
...

Destroy complete! Resources: 13 destroyed.
```

Verify:

```bash
ls output/
```

**Expected output:**
```
ls: cannot access 'output/': No such file or directory
```

Everything is gone. Clean slate.

---

## Key Takeaways

### Mapping Local Concepts to AWS

Every pattern you practiced in this lab has a direct equivalent in AWS. You already know the mechanics -- you just need to swap the resource types.

| Local/Random Pattern | AWS Equivalent | How It Translates |
|----------------------|----------------|-------------------|
| `local_file` | `aws_s3_object` | Writing a file to disk vs uploading to S3 |
| `local_file` with `templatefile()` | `aws_instance` with `user_data` | Templated config vs templated boot script |
| `local_sensitive_file` | `aws_secretsmanager_secret_version` | Sensitive file on disk vs secret in AWS Secrets Manager |
| `random_password` | `random_password` + `aws_secretsmanager_secret` | Same random_password resource, stored in AWS instead of a file |
| `random_id` for unique names | `random_id` + `aws_s3_bucket` | Same pattern: `"bucket-${random_id.this.hex}"` |
| `for_each` over environments | `for_each` over regions or accounts | Same loop, different resources inside |
| `templatefile()` for config | `templatefile()` for EC2 user_data or Lambda config | Same function, different use case |
| `variable` validation | `variable` validation | Identical syntax -- validations work for any variable |
| `locals` for computed values | `locals` for computed values | Same everywhere -- compute once, reference many times |
| `terraform.tfvars` | `terraform.tfvars` or `-var-file=prod.tfvars` | Same mechanism for all providers |

### Terraform Workflow Summary

```
  1. Write       Create/edit .tf files
       |
  2. Init        terraform init (download providers)
       |
  3. Validate    terraform fmt && terraform validate
       |
  4. Plan        terraform plan (dry run)
       |
  5. Apply       terraform apply (create/update resources)
       |
  6. Inspect     terraform output, terraform state list
       |
  7. Update      Edit .tf or .tfvars, repeat from step 4
       |
  8. Destroy     terraform destroy (remove everything)
```

### What You Are Now Ready For

| Skill | Confidence Level |
|-------|-----------------|
| Writing HCL resource blocks | Ready |
| Using variables (string, number, bool, map, object) | Ready |
| Variable validation | Ready |
| Using outputs (including sensitive) | Ready |
| `for_each` to create multiple resources from a map | Ready |
| `locals` for intermediate computed values | Ready |
| `templatefile()` for dynamic content | Ready |
| Understanding `terraform plan` output symbols | Ready |
| Reading and querying state | Ready |
| The full init/plan/apply/destroy lifecycle | Ready |
| Incremental updates (add/change/remove) | Ready |

You have practiced every core Terraform concept without spending a cent on cloud resources. In the next lab (1.3), you will apply these same patterns to deploy your first EC2 instance on AWS -- and it will feel familiar.
