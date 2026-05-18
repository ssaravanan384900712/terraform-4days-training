# Lab 1.4 - Variables, Expressions, and Functions

Terraform's power comes not just from declaring resources but from making those declarations flexible and reusable. This lab covers every aspect of Terraform's variable system -- input variables with all type constraints, output values, locals, validation rules, variable files, environment variables, collection types, built-in functions, and template rendering. You will build a working project that exercises each of these features.

---

## Prerequisites

- Completed Labs 1.2 and 1.3
- Terraform installed and AWS credentials configured

---

## 1. Input Variables

Input variables are the primary mechanism for parameterizing Terraform configurations. They let you customize behavior without changing code.

### 1.1 Variable Declaration Syntax

```hcl
variable "name" {
  description = "Human-readable description"
  type        = <type>
  default     = <default_value>
  sensitive   = true|false
  nullable    = true|false

  validation {
    condition     = <boolean_expression>
    error_message = "Custom error message"
  }
}
```

### 1.2 All Variable Types

Create a new lab directory and explore every variable type:

```bash
mkdir -p ~/terraform-labs/lab-1.4-variables
cd ~/terraform-labs/lab-1.4-variables
```

Create `variables.tf`:

```hcl
# variables.tf - Comprehensive variable type examples

# ------------------------------------------------------------------
# STRING - The most common type
# ------------------------------------------------------------------
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "terraform-lab"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

# ------------------------------------------------------------------
# NUMBER - Integer or floating point
# ------------------------------------------------------------------
variable "instance_count" {
  description = "Number of EC2 instances to create"
  type        = number
  default     = 2
}

variable "server_port" {
  description = "Port for the web server"
  type        = number
  default     = 8080
}

variable "disk_size_gb" {
  description = "Root volume size in GB"
  type        = number
  default     = 20
}

# ------------------------------------------------------------------
# BOOL - true or false
# ------------------------------------------------------------------
variable "enable_monitoring" {
  description = "Enable detailed monitoring for EC2 instances"
  type        = bool
  default     = false
}

variable "create_dns_record" {
  description = "Whether to create a DNS record"
  type        = bool
  default     = true
}

# ------------------------------------------------------------------
# LIST - Ordered collection of values (same type)
# ------------------------------------------------------------------
variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "allowed_ports" {
  description = "List of allowed ingress ports"
  type        = list(number)
  default     = [22, 80, 443, 8080]
}

# ------------------------------------------------------------------
# SET - Unordered collection of unique values
# ------------------------------------------------------------------
variable "allowed_cidr_blocks" {
  description = "Set of CIDR blocks allowed to access the server"
  type        = set(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

# ------------------------------------------------------------------
# MAP - Key-value pairs (same value type)
# ------------------------------------------------------------------
variable "instance_types" {
  description = "Map of environment to instance type"
  type        = map(string)
  default = {
    dev     = "t2.micro"
    staging = "t2.small"
    prod    = "t2.medium"
  }
}

variable "extra_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Team      = "DevOps"
    CostCenter = "12345"
  }
}

# ------------------------------------------------------------------
# OBJECT - Structured type with named attributes
# ------------------------------------------------------------------
variable "database_config" {
  description = "Database configuration"
  type = object({
    engine         = string
    engine_version = string
    instance_class = string
    allocated_storage = number
    multi_az       = bool
  })
  default = {
    engine            = "mysql"
    engine_version    = "8.0"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    multi_az          = false
  }
}

# ------------------------------------------------------------------
# TUPLE - Ordered collection with specific types per element
# ------------------------------------------------------------------
variable "instance_config" {
  description = "Tuple of [instance_type, ami_id, count]"
  type        = tuple([string, string, number])
  default     = ["t2.micro", "ami-0c55b159cbfafe1f0", 1]
}

# ------------------------------------------------------------------
# LIST OF OBJECTS - Common pattern for complex configs
# ------------------------------------------------------------------
variable "ingress_rules" {
  description = "List of ingress rule objects"
  type = list(object({
    port        = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  default = [
    {
      port        = 22
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8"]
      description = "SSH from internal"
    },
    {
      port        = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTP from anywhere"
    },
    {
      port        = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTPS from anywhere"
    }
  ]
}

# ------------------------------------------------------------------
# MAP OF OBJECTS - Another common pattern
# ------------------------------------------------------------------
variable "ec2_instances" {
  description = "Map of instance configurations"
  type = map(object({
    instance_type = string
    ami           = string
    subnet_id     = string
  }))
  default = {}
}

# ------------------------------------------------------------------
# ANY - Accept any type (use sparingly)
# ------------------------------------------------------------------
variable "custom_metadata" {
  description = "Custom metadata of any type"
  type        = any
  default     = null
}

# ------------------------------------------------------------------
# SENSITIVE - Masked in output
# ------------------------------------------------------------------
variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
  default     = "changeme123"
}
```

> **Tip:** Always specify a `type` and `description` for every variable. The `type` constraint catches errors early, and the `description` serves as documentation for anyone using your module.

---

## 2. Output Values

Outputs expose values from your configuration, making them available to:
- The terminal (after apply)
- Other Terraform configurations (via remote state or module outputs)
- Scripts and automation tools

Create `outputs.tf`:

```hcl
# outputs.tf

# ------------------------------------------------------------------
# Basic output
# ------------------------------------------------------------------
output "project_name" {
  description = "The project name"
  value       = var.project_name
}

# ------------------------------------------------------------------
# Computed output
# ------------------------------------------------------------------
output "full_project_name" {
  description = "Full project name with environment"
  value       = "${var.project_name}-${var.environment}"
}

# ------------------------------------------------------------------
# List output
# ------------------------------------------------------------------
output "availability_zones" {
  description = "The configured AZs"
  value       = var.availability_zones
}

# ------------------------------------------------------------------
# Map output
# ------------------------------------------------------------------
output "instance_types_map" {
  description = "Instance type mapping"
  value       = var.instance_types
}

# ------------------------------------------------------------------
# Computed value from map lookup
# ------------------------------------------------------------------
output "selected_instance_type" {
  description = "Instance type for the current environment"
  value       = var.instance_types[var.environment]
}

# ------------------------------------------------------------------
# Sensitive output -- masked in CLI
# ------------------------------------------------------------------
output "db_password" {
  description = "The database password"
  value       = var.db_password
  sensitive   = true
}

# ------------------------------------------------------------------
# Conditional output
# ------------------------------------------------------------------
output "monitoring_status" {
  description = "Whether monitoring is enabled"
  value       = var.enable_monitoring ? "Monitoring ENABLED" : "Monitoring DISABLED"
}

# ------------------------------------------------------------------
# Object attribute output
# ------------------------------------------------------------------
output "database_engine" {
  description = "The database engine"
  value       = var.database_config.engine
}

output "database_summary" {
  description = "Database configuration summary"
  value       = "${var.database_config.engine} ${var.database_config.engine_version} on ${var.database_config.instance_class}"
}
```

### Test outputs

```bash
cd ~/terraform-labs/lab-1.4-variables
terraform init
terraform apply -auto-approve
```

**Expected output:**
```
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

availability_zones     = tolist(["us-east-1a", "us-east-1b", "us-east-1c"])
database_engine        = "mysql"
database_summary       = "mysql 8.0 on db.t3.micro"
db_password            = <sensitive>
full_project_name      = "terraform-lab-dev"
instance_types_map     = tomap({
  "dev"     = "t2.micro"
  "staging" = "t2.small"
  "prod"    = "t2.medium"
})
monitoring_status      = "Monitoring DISABLED"
project_name           = "terraform-lab"
selected_instance_type = "t2.micro"
```

Notice how `db_password` is masked as `<sensitive>`. To view it:

```bash
terraform output db_password
# Still shows <sensitive>

terraform output -raw db_password
# Shows the actual value: changeme123
```

---

## 3. Local Values

Locals are computed values that you define once and reuse throughout your configuration. They reduce repetition and keep your code DRY (Don't Repeat Yourself).

Create `locals.tf`:

```hcl
# locals.tf

locals {
  # Common naming prefix
  name_prefix = "${var.project_name}-${var.environment}"

  # Merge default tags with extra tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.extra_tags
  )

  # Computed values
  is_production = var.environment == "prod"
  instance_type = var.instance_types[var.environment]

  # Conditional logic
  monitoring_enabled = local.is_production ? true : var.enable_monitoring

  # Derived from other locals
  resource_name = "${local.name_prefix}-server"

  # Complex computed value
  server_config = {
    name          = local.resource_name
    instance_type = local.instance_type
    monitoring    = local.monitoring_enabled
    port          = var.server_port
  }
}
```

Add outputs for locals:

```hcl
# Add to outputs.tf

output "name_prefix" {
  description = "The naming prefix"
  value       = local.name_prefix
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

output "server_config" {
  description = "Computed server configuration"
  value       = local.server_config
}
```

```bash
terraform apply -auto-approve
```

**Expected output (partial):**
```
common_tags = tomap({
  "CostCenter"  = "12345"
  "Environment" = "dev"
  "ManagedBy"   = "terraform"
  "Project"     = "terraform-lab"
  "Team"        = "DevOps"
})

name_prefix = "terraform-lab-dev"

server_config = {
  "instance_type" = "t2.micro"
  "monitoring"    = false
  "name"          = "terraform-lab-dev-server"
  "port"          = 8080
}
```

> **Tip:** Use locals for values that are derived from variables or computed from multiple inputs. Use variables for values that the user should be able to change. A good rule of thumb: if you reference the same expression more than twice, make it a local.

---

## 4. Variable Validation

Validation blocks let you add custom constraints to variables, catching invalid input early with clear error messages.

Add these validation examples to `variables.tf` (or update existing variables):

```hcl
# ------------------------------------------------------------------
# Validation Examples
# ------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "The vpc_cidr must be a valid CIDR block (e.g., 10.0.0.0/16)."
  }

  validation {
    condition     = tonumber(split("/", var.vpc_cidr)[1]) <= 24
    error_message = "The VPC CIDR prefix must be /24 or larger (smaller number)."
  }
}

variable "instance_type_validated" {
  description = "EC2 instance type (must be t2 or t3 family)"
  type        = string
  default     = "t2.micro"

  validation {
    condition     = can(regex("^t[23]\\.", var.instance_type_validated))
    error_message = "Instance type must be in the t2 or t3 family (e.g., t2.micro, t3.small)."
  }
}

variable "email" {
  description = "Notification email address"
  type        = string
  default     = "admin@example.com"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.email))
    error_message = "Must be a valid email address."
  }
}

variable "ami_id" {
  description = "Custom AMI ID (must start with ami-)"
  type        = string
  default     = "ami-0c55b159cbfafe1f0"

  validation {
    condition     = length(var.ami_id) > 4 && substr(var.ami_id, 0, 4) == "ami-"
    error_message = "AMI ID must start with 'ami-'."
  }
}
```

### Test validation

```bash
# This should fail -- invalid CIDR
terraform plan -var='vpc_cidr=not-a-cidr'
```

**Expected output:**
```
Error: Invalid value for variable

  on variables.tf line XX:
  XX: variable "vpc_cidr" {

The vpc_cidr must be a valid CIDR block (e.g., 10.0.0.0/16).
```

```bash
# This should fail -- wrong instance family
terraform plan -var='instance_type_validated=m5.large'
```

**Expected output:**
```
Error: Invalid value for variable

  on variables.tf line XX:
  XX: variable "instance_type_validated" {

Instance type must be in the t2 or t3 family (e.g., t2.micro, t3.small).
```

```bash
# This should succeed
terraform plan -var='vpc_cidr=10.0.0.0/16' -var='instance_type_validated=t3.medium'
```

---

## 5. Variable Files

### 5.1 terraform.tfvars (Auto-Loaded)

Create `terraform.tfvars`:

```hcl
# terraform.tfvars - Automatically loaded by Terraform

project_name    = "my-web-app"
environment     = "dev"
instance_count  = 2
server_port     = 8080
disk_size_gb    = 30
enable_monitoring = false
```

### 5.2 Named .tfvars Files

Create `dev.tfvars`:

```hcl
# dev.tfvars

project_name      = "my-web-app"
environment       = "dev"
instance_count    = 1
server_port       = 8080
disk_size_gb      = 20
enable_monitoring = false
instance_types = {
  dev     = "t2.micro"
  staging = "t2.small"
  prod    = "t2.medium"
}
```

Create `staging.tfvars`:

```hcl
# staging.tfvars

project_name      = "my-web-app"
environment       = "staging"
instance_count    = 2
server_port       = 80
disk_size_gb      = 50
enable_monitoring = true
instance_types = {
  dev     = "t2.micro"
  staging = "t2.small"
  prod    = "t2.medium"
}
```

Create `prod.tfvars`:

```hcl
# prod.tfvars

project_name      = "my-web-app"
environment       = "prod"
instance_count    = 4
server_port       = 80
disk_size_gb      = 100
enable_monitoring = true
instance_types = {
  dev     = "t2.micro"
  staging = "t2.small"
  prod    = "t2.medium"
}
```

### Usage

```bash
# Uses terraform.tfvars automatically
terraform plan

# Use a specific var file
terraform plan -var-file="staging.tfvars"

# Use production settings
terraform plan -var-file="prod.tfvars"
```

### 5.3 Auto-Loading Rules

Terraform automatically loads variable files in this order:

1. `terraform.tfvars` (if present)
2. `terraform.tfvars.json` (if present)
3. Any `*.auto.tfvars` or `*.auto.tfvars.json` files (alphabetical order)
4. `-var-file` flag values (in order specified)
5. `-var` flag values (in order specified)

Later values override earlier ones.

Create `common.auto.tfvars`:

```hcl
# common.auto.tfvars - Auto-loaded, alphabetically before terraform.tfvars

extra_tags = {
  Team       = "Platform"
  CostCenter = "99999"
  Owner      = "devops-team"
}
```

> **Tip:** Use `*.auto.tfvars` for values that should always be loaded regardless of environment. Use named `.tfvars` files with `-var-file` for environment-specific values.

---

## 6. Environment Variables

Terraform reads environment variables prefixed with `TF_VAR_` to set variable values.

### 6.1 Setting Variables via Environment

```bash
# Set variables
export TF_VAR_project_name="env-var-project"
export TF_VAR_environment="staging"
export TF_VAR_instance_count=3
export TF_VAR_enable_monitoring=true
export TF_VAR_db_password="super-secret-password"

# Run Terraform -- it picks up the TF_VAR_ variables
terraform plan
```

### 6.2 Precedence (Lowest to Highest)

```
1. Default value in variable declaration (lowest)
2. terraform.tfvars
3. *.auto.tfvars (alphabetical)
4. -var-file flag
5. -var flag
6. TF_VAR_ environment variables (highest)
```

> **Warning:** The actual precedence can be surprising. Environment variables override `-var-file` but `-var` on the command line has the highest precedence of all. Test carefully when mixing methods.

Wait -- let me correct that. The actual precedence from lowest to highest is:

```
1. Default value in variable block
2. terraform.tfvars / terraform.tfvars.json
3. *.auto.tfvars / *.auto.tfvars.json (alphabetical)
4. TF_VAR_ environment variables
5. -var-file flag (in order)
6. -var flag (highest precedence)
```

### 6.3 Practical Example

```bash
# Unset previous env vars
unset TF_VAR_project_name TF_VAR_environment TF_VAR_instance_count
unset TF_VAR_enable_monitoring TF_VAR_db_password

# Set only sensitive values via env vars (best practice)
export TF_VAR_db_password="prod-db-p@ssw0rd!"

# Use var-file for the rest
terraform plan -var-file="prod.tfvars"
```

> **Tip:** The recommended approach for secrets is: use environment variables (`TF_VAR_`) or a secrets manager. Never put sensitive values in `.tfvars` files that get committed to Git.

---

## 7. Maps and Lists -- Practical Patterns

### 7.1 Using Maps for Lookups

Create `main.tf`:

```hcl
# main.tf

# ------------------------------------------------------------------
# Map lookup patterns
# ------------------------------------------------------------------

# Look up the instance type for the current environment
locals {
  # Direct index notation
  current_instance_type = var.instance_types[var.environment]

  # Using lookup() with a default fallback
  ami_by_region = {
    "us-east-1" = "ami-0c55b159cbfafe1f0"
    "us-west-2" = "ami-0892d3c7ee96c0bf7"
    "eu-west-1" = "ami-0d75513e7706cf2d9"
  }

  selected_ami = lookup(local.ami_by_region, "us-east-1", "ami-default")
}

output "current_instance_type" {
  value = local.current_instance_type
}

output "selected_ami" {
  value = local.selected_ami
}
```

### 7.2 Using Lists with count

```hcl
# List indexing
variable "subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

output "first_subnet" {
  value = var.subnet_cidrs[0]
}

output "all_subnets" {
  value = var.subnet_cidrs
}

output "subnet_count" {
  value = length(var.subnet_cidrs)
}
```

### 7.3 Iterating Over Maps with for_each

```hcl
variable "users" {
  type = map(object({
    role  = string
    email = string
  }))
  default = {
    alice = {
      role  = "admin"
      email = "alice@example.com"
    }
    bob = {
      role  = "developer"
      email = "bob@example.com"
    }
    carol = {
      role  = "readonly"
      email = "carol@example.com"
    }
  }
}

output "user_emails" {
  value = { for name, user in var.users : name => user.email }
}

output "admin_users" {
  value = [for name, user in var.users : name if user.role == "admin"]
}
```

```bash
terraform apply -auto-approve
```

**Expected output (partial):**
```
admin_users = [
  "alice",
]
user_emails = {
  "alice" = "alice@example.com"
  "bob"   = "bob@example.com"
  "carol" = "carol@example.com"
}
```

---

## 8. Built-in Functions

Terraform has dozens of built-in functions. You can test them interactively using `terraform console`:

```bash
terraform console
```

### 8.1 Numeric Functions

```hcl
# In terraform console:

> max(5, 12, 9)
12

> min(5, 12, 9)
5

> abs(-42)
42

> ceil(4.3)
5

> floor(4.9)
4

> pow(2, 8)
256

> signum(-5)
-1

> parseint("FF", 16)
255
```

### 8.2 String Functions

```hcl
> upper("hello terraform")
"HELLO TERRAFORM"

> lower("HELLO TERRAFORM")
"hello terraform"

> title("hello terraform")
"Hello Terraform"

> trim("  hello  ", " ")
"hello"

> trimprefix("helloworld", "hello")
"world"

> trimsuffix("helloworld", "world")
"hello"

> replace("hello world", "world", "terraform")
"hello terraform"

> substr("hello world", 0, 5)
"hello"

> split(",", "a,b,c,d")
tolist(["a", "b", "c", "d"])

> join("-", ["a", "b", "c"])
"a-b-c"

> format("Hello, %s! You have %d servers.", "Alice", 5)
"Hello, Alice! You have 5 servers."

> formatlist("server-%s", ["web", "app", "db"])
["server-web", "server-app", "server-db"]

> regex("^ami-([a-z0-9]+)$", "ami-0c55b159cbfafe1f0")
["0c55b159cbfafe1f0"]

> regexall("[a-z]+", "Hello World 123")
[["ello"], ["orld"]]

> startswith("hello", "hel")
true

> endswith("hello.tf", ".tf")
true

> strcontains("hello world", "world")
true
```

### 8.3 Collection Functions

```hcl
> length(["a", "b", "c"])
3

> length({a = 1, b = 2})
2

> contains(["a", "b", "c"], "b")
true

> contains(["a", "b", "c"], "d")
false

> distinct(["a", "b", "a", "c", "b"])
tolist(["a", "b", "c"])

> flatten([["a", "b"], ["c"], ["d", "e"]])
["a", "b", "c", "d", "e"]

> sort(["c", "a", "b"])
tolist(["a", "b", "c"])

> reverse(["a", "b", "c"])
["c", "b", "a"]

> compact(["a", "", "b", "", "c"])
tolist(["a", "b", "c"])

> coalesce("", "", "hello", "world")
"hello"

> coalescelist([], [], ["a", "b"])
["a", "b"]

> merge({a = 1, b = 2}, {b = 3, c = 4})
{a = 1, b = 3, c = 4}

> keys({a = 1, b = 2, c = 3})
["a", "b", "c"]

> values({a = 1, b = 2, c = 3})
[1, 2, 3]

> lookup({a = 1, b = 2}, "a", 0)
1

> lookup({a = 1, b = 2}, "c", 0)
0

> element(["a", "b", "c"], 1)
"b"

> slice(["a", "b", "c", "d", "e"], 1, 4)
["b", "c", "d"]

> range(5)
[0, 1, 2, 3, 4]

> range(1, 10, 2)
[1, 3, 5, 7, 9]

> zipmap(["name", "age", "city"], ["Alice", "30", "NYC"])
{"age" = "30", "city" = "NYC", "name" = "Alice"}

> one([])
null

> one(["hello"])
"hello"
```

### 8.4 Type Conversion Functions

```hcl
> tostring(42)
"42"

> tonumber("42")
42

> tobool("true")
true

> tolist(toset(["c", "a", "b", "a"]))
["a", "b", "c"]

> toset(["a", "b", "a"])
["a", "b"]

> tomap({name = "alice", age = "30"})
{"age" = "30", "name" = "alice"}

> try(tonumber("hello"), 0)
0

> can(tonumber("hello"))
false

> can(tonumber("42"))
true
```

### 8.5 Encoding Functions

```hcl
> jsonencode({name = "alice", items = [1, 2, 3]})
"{\"items\":[1,2,3],\"name\":\"alice\"}"

> jsondecode("{\"name\":\"alice\"}")
{"name" = "alice"}

> base64encode("hello terraform")
"aGVsbG8gdGVycmFmb3Jt"

> base64decode("aGVsbG8gdGVycmFmb3Jt")
"hello terraform"

> urlencode("hello world & terraform")
"hello+world+%26+terraform"

> yamlencode({name = "alice", ports = [80, 443]})
# Returns YAML-formatted string
```

### 8.6 Filesystem Functions

```hcl
> file("${path.module}/variables.tf")
# Returns the contents of variables.tf

> fileexists("${path.module}/variables.tf")
true

> fileexists("${path.module}/nonexistent.tf")
false

> basename("/path/to/file.txt")
"file.txt"

> dirname("/path/to/file.txt")
"/path/to"
```

### 8.7 Date and Time Functions

```hcl
> timestamp()
"2024-01-15T10:30:00Z"

> formatdate("YYYY-MM-DD", timestamp())
"2024-01-15"

> formatdate("DD MMM YYYY hh:mm", timestamp())
"15 Jan 2024 10:30"

> timeadd(timestamp(), "24h")
"2024-01-16T10:30:00Z"

> timecmp("2024-01-15T00:00:00Z", "2024-01-16T00:00:00Z")
-1
```

### 8.8 IP Network Functions

```hcl
> cidrsubnet("10.0.0.0/16", 8, 1)
"10.0.1.0/24"

> cidrsubnet("10.0.0.0/16", 8, 2)
"10.0.2.0/24"

> cidrhost("10.0.1.0/24", 5)
"10.0.1.5"

> cidrnetmask("10.0.0.0/16")
"255.255.0.0"
```

Exit the console:

```bash
> exit
```

---

## 9. Templates with templatefile()

The `templatefile()` function renders a template file with variable substitutions. This is ideal for generating user_data scripts, configuration files, and policy documents.

### Step 1: Create the template file

Create `templates/user_data.sh.tpl`:

```bash
mkdir -p ~/terraform-labs/lab-1.4-variables/templates
```

```bash
cat > ~/terraform-labs/lab-1.4-variables/templates/user_data.sh.tpl << 'TEMPLATE'
#!/bin/bash
set -euo pipefail

# ====================================
# Server Configuration
# Generated by Terraform
# ====================================

echo "Setting up ${server_name}..."
echo "Environment: ${environment}"
echo "Port: ${server_port}"

# Install packages
yum update -y
yum install -y httpd

# Configure Apache
cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
  <title>${server_name}</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 40px; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
    th { background-color: #4CAF50; color: white; }
    tr:nth-child(even) { background-color: #f2f2f2; }
  </style>
</head>
<body>
  <h1>${server_name}</h1>
  <h2>Environment: ${environment}</h2>
  <table>
    <tr><th>Setting</th><th>Value</th></tr>
    <tr><td>Port</td><td>${server_port}</td></tr>
    <tr><td>Instance Type</td><td>${instance_type}</td></tr>
    <tr><td>Disk Size</td><td>${disk_size} GB</td></tr>
    <tr><td>Monitoring</td><td>${monitoring_enabled ? "Enabled" : "Disabled"}</td></tr>
%{ for key, value in tags ~}
    <tr><td>${key}</td><td>${value}</td></tr>
%{ endfor ~}
  </table>

  <h3>Allowed Ports</h3>
  <ul>
%{ for port in allowed_ports ~}
    <li>Port ${port}</li>
%{ endfor ~}
  </ul>
</body>
</html>
HTMLEOF

# Start Apache on the configured port
sed -i 's/Listen 80/Listen ${server_port}/' /etc/httpd/conf/httpd.conf
systemctl start httpd
systemctl enable httpd

echo "Setup complete!"
TEMPLATE
```

### Step 2: Create a policy template

Create `templates/iam_policy.json.tpl`:

```bash
cat > ~/terraform-labs/lab-1.4-variables/templates/iam_policy.json.tpl << 'TEMPLATE'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
%{ for i, bucket in s3_buckets ~}
        "arn:aws:s3:::${bucket}",
        "arn:aws:s3:::${bucket}/*"${ i < length(s3_buckets) - 1 ? "," : "" }
%{ endfor ~}
      ]
    },
    {
      "Effect": "Allow",
      "Action": "logs:*",
      "Resource": "arn:aws:logs:${region}:${account_id}:*"
    }
  ]
}
TEMPLATE
```

### Step 3: Use templatefile() in your configuration

Add to `main.tf`:

```hcl
# ------------------------------------------------------------------
# Template rendering examples
# ------------------------------------------------------------------

locals {
  # Render the user_data template
  user_data_script = templatefile("${path.module}/templates/user_data.sh.tpl", {
    server_name        = local.name_prefix
    environment        = var.environment
    server_port        = var.server_port
    instance_type      = local.current_instance_type
    disk_size          = var.disk_size_gb
    monitoring_enabled = local.monitoring_enabled
    tags               = local.common_tags
    allowed_ports      = var.allowed_ports
  })

  # Render the IAM policy template
  iam_policy = templatefile("${path.module}/templates/iam_policy.json.tpl", {
    s3_buckets = ["my-app-data", "my-app-logs", "my-app-backups"]
    region     = "us-east-1"
    account_id = "123456789012"
  })
}

output "rendered_user_data" {
  description = "The rendered user_data script (first 500 chars)"
  value       = substr(local.user_data_script, 0, 500)
}

output "rendered_iam_policy" {
  description = "The rendered IAM policy"
  value       = local.iam_policy
}
```

### Step 4: Apply and verify

```bash
terraform apply -auto-approve
```

**Expected output (partial):**
```
rendered_iam_policy = <<-EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-app-data",
        "arn:aws:s3:::my-app-data/*",
        "arn:aws:s3:::my-app-logs",
        ...
      ]
    },
    ...
  ]
}
EOT
```

### Step 5: Use the template in an actual resource

Here is how you would use the rendered user_data in an EC2 instance:

```hcl
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = local.current_instance_type

  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    server_name        = local.name_prefix
    environment        = var.environment
    server_port        = var.server_port
    instance_type      = local.current_instance_type
    disk_size          = var.disk_size_gb
    monitoring_enabled = local.monitoring_enabled
    tags               = local.common_tags
    allowed_ports      = var.allowed_ports
  })

  tags = merge(local.common_tags, {
    Name = local.resource_name
  })
}
```

> **Tip:** `templatefile()` is far superior to inline `heredoc` strings for complex scripts. It keeps your HCL clean, makes templates testable independently, and supports loops and conditionals via `%{ for }` and `%{ if }` directives.

---

## 10. Quick Reference -- Variable Precedence

From lowest to highest priority:

| Priority | Source | Example |
|----------|--------|---------|
| 1 (lowest) | Default in variable block | `default = "t2.micro"` |
| 2 | `terraform.tfvars` | `instance_type = "t2.small"` |
| 3 | `*.auto.tfvars` (alphabetical) | `common.auto.tfvars` |
| 4 | `TF_VAR_` environment variable | `export TF_VAR_instance_type=t2.medium` |
| 5 | `-var-file` flag | `terraform plan -var-file=prod.tfvars` |
| 6 (highest) | `-var` flag | `terraform plan -var='instance_type=t3.large'` |

---

## 11. Cleanup

```bash
# Destroy any resources if created
terraform destroy -auto-approve

# Clean up environment variables
unset TF_VAR_db_password
```

---

## Summary

| Topic | Key Takeaway |
|-------|-------------|
| Input Variables | Parameterize configs with type constraints |
| Variable Types | string, number, bool, list, set, map, object, tuple, any |
| Outputs | Expose values to CLI, scripts, and other configs |
| Locals | Computed values for DRY code |
| Validation | Custom constraints with clear error messages |
| Variable Files | `.tfvars` for environment-specific values |
| Environment Variables | `TF_VAR_` prefix for secrets and CI/CD |
| Functions | 100+ built-in functions for strings, numbers, collections |
| Templates | `templatefile()` for complex file generation |

In the next lab, you will learn about resource dependencies, lifecycle rules, and your first Terraform module.
