# Hands-On 1.2b -- Random Provider: Generating Dynamic Values

In the previous lab you created static files with the local provider. Now you will learn the **random provider**, which generates unique values like pet names, passwords, IDs, and UUIDs. This provider is used constantly in real Terraform projects to avoid naming conflicts, generate secrets, and create reproducible randomness. You will also learn **idempotency**, **keepers**, **count**, and **for_each** -- all without needing a cloud account.

---

## Concept

### Why the Random Provider?

In cloud environments, many resource names must be globally unique (S3 bucket names, database identifiers, DNS names). If two teammates both run `terraform apply` with the same hardcoded name, one of them fails. The random provider solves this:

```
  Your Code                Random Provider             Cloud Resource
  +-----------+            +----------------+           +--------------------+
  | app_name  | ---------> | random_pet     | --------> | S3 bucket:         |
  | = "web"   |            | = "web-calm-   |           | "web-calm-panda-   |
  |           |            |    panda"      |           |  a3f8c1"           |
  +-----------+            +----------------+           +--------------------+
                                  |
                           Stored in state
                           (same value on
                            next apply)
```

### Random Provider Resources

| Resource | Generates | Example Output |
|----------|-----------|----------------|
| `random_pet` | Human-readable name | `calm-panda` |
| `random_string` | Arbitrary string | `xK9#mP2q` |
| `random_integer` | Number in a range | `8452` |
| `random_id` | Base64/hex identifier | `a3f8c1b2` |
| `random_uuid` | UUID v4 | `550e8400-e29b-41d4-a716-446655440000` |
| `random_shuffle` | Shuffled list | `["b", "c", "a"]` |
| `random_password` | Password (sensitive) | `Xk9#mP2q!wR5` |

### Key Concept: Idempotency

Terraform is **idempotent** -- running `apply` twice produces the same result. A random value is generated **once** and stored in state. Subsequent applies return the same value. This is critical: your "random" pet name stays the same across deployments until you explicitly force recreation.

---

## Step-by-Step

### Exercise 1: random_pet -- Human-Readable Names

#### Step 1: Create a project directory

```bash
mkdir -p ~/terraform-labs/lab-random
cd ~/terraform-labs/lab-random
```

#### Step 2: Write the configuration

Create `main.tf`:

```hcl
# main.tf -- Random pet name generator

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

resource "random_pet" "server_name" {
  length    = 2        # Number of words (e.g., "calm-panda")
  separator = "-"      # Word separator
}

output "pet_name" {
  value = random_pet.server_name.id
}
```

#### Step 3: Initialize

```bash
terraform init
```

**Expected output:**
```
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/random versions matching "~> 3.0"...
- Installing hashicorp/random v3.6.3...
- Installed hashicorp/random v3.6.3 (signed by HashiCorp)

Terraform has been successfully initialized!
```

#### Step 4: Plan

```bash
terraform plan
```

**Expected output:**
```
Terraform will perform the following actions:

  # random_pet.server_name will be created
  + resource "random_pet" "server_name" {
      + id        = (known after apply)
      + length    = 2
      + separator = "-"
    }

Plan: 1 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + pet_name = (known after apply)
```

The `id` is `(known after apply)` because the random value does not exist until Terraform creates it.

#### Step 5: Apply

```bash
terraform apply
```

Type `yes`.

**Expected output:**
```
random_pet.server_name: Creating...
random_pet.server_name: Creation complete after 0s [id=helping-piranha]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

pet_name = "helping-piranha"
```

Your pet name will be different -- that is the point.

#### Step 6: Prove idempotency -- apply again

```bash
terraform apply
```

**Expected output:**
```
random_pet.server_name: Refreshing state... [id=helping-piranha]

No changes. Your infrastructure matches the configuration.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

pet_name = "helping-piranha"
```

**The name did not change.** This is idempotency in action. The random value was generated once, stored in state, and reused. Running `apply` ten more times will give the same result.

> **Tip:** Idempotency is a core Terraform principle. It means "applying the same configuration always produces the same result." This is what makes Terraform safe to run repeatedly.

---

### Exercise 2: random_string -- Generating a Password

#### Step 1: Add to `main.tf`

Append the following to `main.tf`:

```hcl
resource "random_string" "db_password" {
  length  = 16
  special = true       # Include !@#$%^&*() etc.
  upper   = true
  lower   = true
  numeric = true
}

output "db_password" {
  value     = random_string.db_password.result
  sensitive = true     # Hide from plan/apply output
}
```

#### Step 2: Apply

```bash
terraform apply
```

Type `yes`.

**Expected output:**
```
random_pet.server_name: Refreshing state... [id=helping-piranha]
random_string.db_password: Creating...
random_string.db_password: Creation complete after 0s [id=Xk9#mP2q!wR5tL8b]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

db_password = <sensitive>
pet_name    = "helping-piranha"
```

Notice `db_password = <sensitive>`. Terraform hides the value because we set `sensitive = true`.

#### Step 3: Retrieve the sensitive value

```bash
terraform output db_password
```

**Expected output:**
```
"Xk9#mP2q!wR5tL8b"
```

```bash
# Raw value (no quotes) for scripts
terraform output -raw db_password
```

> **Warning:** Sensitive values are hidden from plan/apply console output and logs, but they are still stored in plain text in the state file. Always encrypt your state file in production.

---

### Exercise 3: random_integer -- Random Port Number

Append to `main.tf`:

```hcl
resource "random_integer" "port" {
  min = 8000
  max = 9000
}

output "server_port" {
  value = random_integer.port.result
}
```

```bash
terraform apply
```

Type `yes`.

**Expected output (partial):**
```
random_integer.port: Creating...
random_integer.port: Creation complete after 0s [id=8452]

Outputs:

db_password = <sensitive>
pet_name    = "helping-piranha"
server_port = 8452
```

Your port number will be different but will be between 8000 and 9000.

---

### Exercise 4: random_id -- Unique Identifier

The `random_id` resource generates a fixed-length random byte sequence and exposes it in multiple formats.

Append to `main.tf`:

```hcl
resource "random_id" "deploy" {
  byte_length = 8
}

output "deploy_id_hex" {
  value = random_id.deploy.hex
}

output "deploy_id_dec" {
  value = random_id.deploy.dec
}

output "deploy_id_b64" {
  value = random_id.deploy.b64_url
}
```

```bash
terraform apply
```

Type `yes`.

**Expected output (partial):**
```
random_id.deploy: Creating...
random_id.deploy: Creation complete after 0s [id=o_Nz5Q8XZAM]

Outputs:

db_password   = <sensitive>
deploy_id_b64 = "o_Nz5Q8XZAM"
deploy_id_dec = "11610823479236099077"
deploy_id_hex = "a3f373e50f176403"
pet_name      = "helping-piranha"
server_port   = 8452
```

Now let us use this ID in a real filename. Add to `main.tf`:

```hcl
resource "local_file" "deploy_config" {
  filename = "${path.module}/config-${random_id.deploy.hex}.txt"
  content  = "Deployment ID: ${random_id.deploy.hex}\nGenerated by Terraform\n"
}

output "config_file" {
  value = local_file.deploy_config.filename
}
```

You also need to add the local provider. Update the `required_providers` block:

```hcl
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
```

```bash
terraform init    # Needed because we added a new provider
terraform apply
```

Type `yes`.

**Expected output (partial):**
```
local_file.deploy_config: Creating...
local_file.deploy_config: Creation complete after 0s [id=...]

Outputs:

config_file   = "./config-a3f373e50f176403.txt"
...
```

```bash
cat config-*.txt
```

**Expected output:**
```
Deployment ID: a3f373e50f176403
Generated by Terraform
```

This is a common pattern: use `random_id` to generate unique names for cloud resources like S3 buckets, database instances, or log groups.

---

### Exercise 5: random_uuid -- UUID Generation

Append to `main.tf`:

```hcl
resource "random_uuid" "request_id" {}

output "request_uuid" {
  value = random_uuid.request_id.result
}
```

```bash
terraform apply
```

Type `yes`.

**Expected output (partial):**
```
random_uuid.request_id: Creating...
random_uuid.request_id: Creation complete after 0s [id=550e8400-e29b-41d4-a716-446655440000]

Outputs:

...
request_uuid = "550e8400-e29b-41d4-a716-446655440000"
```

UUIDs are useful for tagging deployments, correlating logs, or generating unique identifiers that follow the standard UUID v4 format.

---

### Exercise 6: random_shuffle -- Shuffling Lists

Append to `main.tf`:

```hcl
resource "random_shuffle" "az" {
  input = [
    "us-east-1a",
    "us-east-1b",
    "us-east-1c",
    "us-east-1d",
    "us-east-1e",
    "us-east-1f",
  ]
  result_count = 2
}

output "selected_azs" {
  value = random_shuffle.az.result
}
```

```bash
terraform apply
```

Type `yes`.

**Expected output (partial):**
```
random_shuffle.az: Creating...
random_shuffle.az: Creation complete after 0s [id=-]

Outputs:

...
selected_azs = [
  "us-east-1c",
  "us-east-1a",
]
```

Your two selected availability zones will be different. This pattern is useful for randomly distributing resources across zones for resilience testing.

---

### Exercise 7: Keepers -- Controlling When Values Regenerate

By default, random values never change once created. **Keepers** let you tie a random value to an external value. When the keeper changes, the random value is **destroyed and recreated**.

#### Step 1: Add a variable and a kept resource

Add to `variables.tf` (create the file if it does not exist):

```hcl
# variables.tf

variable "project_name" {
  description = "Project name -- changing this regenerates the random values"
  type        = string
  default     = "alpha"
}
```

Append to `main.tf`:

```hcl
resource "random_pet" "kept_name" {
  length = 2

  keepers = {
    project = var.project_name
  }
}

output "kept_pet_name" {
  value = random_pet.kept_name.id
}
```

#### Step 2: Apply

```bash
terraform apply
```

Type `yes`. Note the `kept_pet_name` output (e.g., `busy-eagle`).

#### Step 3: Apply again -- no change

```bash
terraform apply
```

**Expected output:**
```
No changes. Your infrastructure matches the configuration.
```

The name stays the same because `var.project_name` is still `"alpha"`.

#### Step 4: Change the keeper value

```bash
terraform apply -var="project_name=beta"
```

**Expected output:**
```
  # random_pet.kept_name must be replaced
-/+ resource "random_pet" "kept_name" {
      ~ id        = "busy-eagle" -> (known after apply)
      ~ keepers   = {
          ~ "project" = "alpha" -> "beta"
        }
        # (2 unchanged attributes hidden)
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

Notice the `-/+` symbol -- this means **destroy and recreate**. The keeper changed, so the random value is regenerated.

Type `yes`.

**Expected output:**
```
random_pet.kept_name: Destroying... [id=busy-eagle]
random_pet.kept_name: Destruction complete after 0s
random_pet.kept_name: Creating...
random_pet.kept_name: Creation complete after 0s [id=light-mackerel]

Outputs:

kept_pet_name = "light-mackerel"
```

A completely new name. This is the same concept as "forces replacement" in AWS -- changing an AMI ID forces an EC2 instance to be destroyed and recreated. You just learned that concept without touching AWS.

> **Tip:** Keepers are a map of string values. You can include multiple keepers. If **any** keeper value changes, the resource is recreated.

---

### Exercise 8: Combining Random and Local Providers

Let us chain resources together. The random provider generates a name, and the local provider uses it.

#### Step 1: Create a new file `combined.tf`

```hcl
# combined.tf -- Chaining random + local providers

resource "random_pet" "app_name" {
  length    = 3
  separator = "-"
}

resource "local_file" "app_config" {
  filename = "${path.module}/app-${random_pet.app_name.id}.conf"
  content  = <<-EOF
    # Application Configuration
    # Auto-generated by Terraform
    app_name    = "${random_pet.app_name.id}"
    deploy_id   = "${random_id.deploy.hex}"
    server_port = ${random_integer.port.result}
    request_id  = "${random_uuid.request_id.result}"
  EOF
}

output "app_config_file" {
  value = local_file.app_config.filename
}
```

#### Step 2: Apply

```bash
terraform apply
```

Type `yes`.

**Expected output (partial):**
```
random_pet.app_name: Creating...
random_pet.app_name: Creation complete after 0s [id=intensely-pumped-lemur]
local_file.app_config: Creating...
local_file.app_config: Creation complete after 0s [id=...]

Outputs:

app_config_file = "./app-intensely-pumped-lemur.conf"
...
```

```bash
cat app-*.conf
```

**Expected output:**
```
# Application Configuration
# Auto-generated by Terraform
app_name    = "intensely-pumped-lemur"
deploy_id   = "a3f373e50f176403"
server_port = 8452
request_id  = "550e8400-e29b-41d4-a716-446655440000"
```

This demonstrates **resource dependencies**. Terraform automatically knows that `local_file.app_config` depends on `random_pet.app_name` because the content references `random_pet.app_name.id`. It creates the random pet first, then the file.

You can visualize this:

```
random_pet.app_name ----+
random_id.deploy -------+---> local_file.app_config
random_integer.port ----+
random_uuid.request_id -+
```

> **Tip:** You can see the dependency graph with `terraform graph`. The output is in DOT format and can be visualized with Graphviz.

---

### Exercise 9: count -- Creating Multiple Resources

The `count` meta-argument lets you create multiple copies of a resource.

#### Step 1: Create `count.tf`

```hcl
# count.tf -- Creating multiple random resources with count

resource "random_pet" "team_members" {
  count  = 3
  length = 2
}

output "team_member_names" {
  value = random_pet.team_members[*].id
}
```

The `[*]` is called a **splat expression**. It collects a single attribute from all instances into a list.

#### Step 2: Apply

```bash
terraform apply
```

Type `yes`.

**Expected output (partial):**
```
random_pet.team_members[0]: Creating...
random_pet.team_members[1]: Creating...
random_pet.team_members[2]: Creating...
random_pet.team_members[0]: Creation complete after 0s [id=fit-turtle]
random_pet.team_members[1]: Creation complete after 0s [id=grand-puma]
random_pet.team_members[2]: Creation complete after 0s [id=witty-shark]

Outputs:

team_member_names = [
  "fit-turtle",
  "grand-puma",
  "witty-shark",
]
```

Three unique pet names, accessed as a list.

#### Step 3: Examine the state

```bash
terraform state list | grep team
```

**Expected output:**
```
random_pet.team_members[0]
random_pet.team_members[1]
random_pet.team_members[2]
```

Each instance has a numeric index in the state.

> **Tip:** `count` is useful when you need N identical (or nearly identical) copies of a resource. For resources that differ by a key (like environments), use `for_each` instead.

---

### Exercise 10: for_each -- Creating Resources from a Map

`for_each` creates one resource instance per item in a map or set. Each instance is identified by its key, not a numeric index.

#### Step 1: Create `foreach.tf`

```hcl
# foreach.tf -- Creating per-environment resources with for_each

variable "environments" {
  description = "Map of environments and their password lengths"
  type        = map(number)
  default = {
    dev     = 12
    staging = 16
    prod    = 24
  }
}

resource "random_string" "env_password" {
  for_each = var.environments

  length  = each.value    # Password length from the map value
  special = true
  upper   = true
  lower   = true
  numeric = true
}

output "env_passwords" {
  value     = { for env, pw in random_string.env_password : env => pw.result }
  sensitive = true
}

output "env_password_lengths" {
  value = { for env, pw in random_string.env_password : env => length(pw.result) }
}
```

Key concepts:

| Expression | Meaning |
|------------|---------|
| `for_each = var.environments` | Create one instance per map entry |
| `each.key` | The map key (`dev`, `staging`, `prod`) |
| `each.value` | The map value (`12`, `16`, `24`) |
| `{ for env, pw in ... }` | A **for expression** that builds a new map from the results |

#### Step 2: Apply

```bash
terraform apply
```

Type `yes`.

**Expected output (partial):**
```
random_string.env_password["dev"]: Creating...
random_string.env_password["prod"]: Creating...
random_string.env_password["staging"]: Creating...
random_string.env_password["dev"]: Creation complete after 0s [id=Xk9#mP2q!wR5]
random_string.env_password["staging"]: Creation complete after 0s [id=aB3$cD5^eF7*gH9!]
random_string.env_password["prod"]: Creation complete after 0s [id=xY1@zW2#qR3$tU4%vB5^nM6*pL7!hJ8]

Outputs:

env_password_lengths = {
  "dev"     = 12
  "prod"    = 24
  "staging" = 16
}
env_passwords = <sensitive>
```

#### Step 3: Examine the state

```bash
terraform state list | grep env_password
```

**Expected output:**
```
random_string.env_password["dev"]
random_string.env_password["prod"]
random_string.env_password["staging"]
```

Notice the keys are strings (`"dev"`, `"staging"`, `"prod"`), not numbers. This is a major advantage over `count`: if you remove `staging` from the map, only `staging` is destroyed. With `count`, removing index 1 would shift all subsequent resources.

#### Step 4: Retrieve specific passwords

```bash
terraform output env_passwords
```

**Expected output:**
```
{
  "dev"     = "Xk9#mP2q!wR5"
  "prod"    = "xY1@zW2#qR3$tU4%vB5^nM6*pL7!hJ8"
  "staging" = "aB3$cD5^eF7*gH9!"
}
```

| count vs for_each | When to Use |
|-------------------|-------------|
| `count` | N identical copies, referenced by index |
| `for_each` | Resources that differ by key (environments, regions, users) |

---

### Cleanup

```bash
terraform destroy
```

Type `yes`. All random values and local files are removed.

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| `random_pet` | Human-readable random names |
| `random_string` | Arbitrary random strings and passwords |
| `random_integer` | Random numbers in a range |
| `random_id` | Fixed-length hex/base64 identifiers |
| `random_uuid` | Standard UUID v4 values |
| `random_shuffle` | Randomly select/reorder items from a list |
| Idempotency | `apply` twice = same result (random values persist in state) |
| Keepers | Tie a random value to an external value; changing the keeper forces recreation |
| Resource dependencies | Terraform detects references and creates resources in the correct order |
| `count` | Create N copies of a resource, indexed by number |
| `for_each` | Create one resource per map/set item, indexed by key |
| Splat `[*]` | Collect an attribute from all `count` instances into a list |
| `sensitive = true` | Hide values from console output |

These are the same patterns you will use in AWS. The only difference is the provider -- instead of `random_pet`, you will create `aws_instance`. Instead of `for_each` over environments, you will iterate over regions or accounts. The mechanics are identical.

In the next lab, you will combine everything into a mini project: a **Config File Generator** that uses both the local and random providers together.
