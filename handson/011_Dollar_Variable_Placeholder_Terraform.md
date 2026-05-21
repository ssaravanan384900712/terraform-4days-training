# 011 Dollar Variable Placeholder Terraform

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~10 minutes

## Demo Goal

This demo explains how Terraform variable placeholders work using the **Random provider only**.

This version creates a local random string and combines it with a user-provided prefix using Terraform interpolation:

```hcl
"${var.name_prefix}_${random_string.rs.id}"
```

This is useful for learning:

- Terraform variables
- Random provider usage
- Dollar variable placeholder syntax
- String interpolation
- How values become known after `terraform apply`

---

## Folder Name

```bash
mkdir -p ~/tf_random_placeholder
cd ~/tf_random_placeholder
```

---

## File Structure

```bash
~/tf_random_placeholder
├── main.tf
├── variables.tf
├── providers.tf
└── outputs.tf
```

---

## 1. Create `providers.tf`

```bash
cat > providers.tf <<'EOF_PROVIDER'
terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
EOF_PROVIDER
```

### Explanation

The `random` provider is a Terraform provider from HashiCorp.

It does not need Azure, AWS, GCP, or any cloud account.

It can generate random values such as:

- Random strings
- Random passwords
- Random integers
- Random pet names
- Random UUIDs

---

## 2. Create `variables.tf`

```bash
cat > variables.tf <<'EOF_VARIABLES'
variable "name_prefix" {
  description = "Prefix to add before the random string"
  type        = string
}

variable "string_length" {
  description = "Length of the random string"
  type        = number
  default     = 12
}
EOF_VARIABLES
```

### Explanation

This file defines two variables.

| Variable | Purpose |
|---|---|
| `name_prefix` | User-provided text that appears before the random string |
| `string_length` | Length of the generated random string |

Because `name_prefix` does not have a default value, Terraform will ask for it during `terraform apply`.

---

## 3. Create `main.tf`

```bash
cat > main.tf <<'EOF_MAIN'
resource "random_string" "rs" {
  special = false
  length  = var.string_length
}

locals {
  final_name = "${var.name_prefix}_${random_string.rs.id}"
}
EOF_MAIN
```

### Important Line

```hcl
final_name = "${var.name_prefix}_${random_string.rs.id}"
```

This line combines:

```hcl
var.name_prefix
```

with:

```hcl
random_string.rs.id
```

using this format:

```text
prefix_randomstring
```

Example:

```text
robochef_TKDKdeuWzuJp
```

---

## 4. Create `outputs.tf`

```bash
cat > outputs.tf <<'EOF_OUTPUTS'
output "random_string_id" {
  description = "Generated random string ID"
  value       = random_string.rs.id
}

output "final_name" {
  description = "Final name created using variable placeholder interpolation"
  value       = local.final_name
}
EOF_OUTPUTS
```

### Explanation

Outputs show values after Terraform finishes running.

Here we print:

- The generated random string
- The final combined name

---

## 5. Check Files

```bash
ls
```

Expected output:

```text
main.tf  outputs.tf  providers.tf  variables.tf
```

View the files:

```bash
cat providers.tf
cat variables.tf
cat main.tf
cat outputs.tf
```

---

## 6. Initialize Terraform

```bash
terraform init
```

Expected result:

```text
Terraform has been successfully initialized!
```

Terraform downloads the `hashicorp/random` provider plugin.

---

## 7. Run Terraform Plan

```bash
terraform plan
```

Terraform will ask for `name_prefix`:

```text
var.name_prefix
  Prefix to add before the random string

  Enter a value: robochef
```

Example plan output:

```text
Terraform will perform the following actions:

  # random_string.rs will be created
  + resource "random_string" "rs" {
      + id          = (known after apply)
      + length      = 12
      + lower       = true
      + numeric     = true
      + special     = false
      + upper       = true
      + result      = (known after apply)
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

### Key Point

The random value is shown as:

```text
known after apply
```

This means Terraform does not know the final random value until the resource is actually created.

---

## 8. Apply Terraform

```bash
terraform apply
```

Enter the prefix:

```text
var.name_prefix
  Prefix to add before the random string

  Enter a value: robochef
```

Approve the apply:

```text
Enter a value: yes
```

Example output:

```text
random_string.rs: Creating...
random_string.rs: Creation complete after 0s [id=TKDKdeuWzuJp]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

final_name = "robochef_TKDKdeuWzuJp"
random_string_id = "TKDKdeuWzuJp"
```

---

## 9. What Happened?

Terraform generated this random string:

```text
TKDKdeuWzuJp
```

The user entered this prefix:

```text
robochef
```

Terraform combined them using:

```hcl
"${var.name_prefix}_${random_string.rs.id}"
```

Final output:

```text
robochef_TKDKdeuWzuJp
```

---

## 10. Understanding Dollar Placeholder Syntax

Terraform interpolation uses this format:

```hcl
"${expression}"
```

Example:

```hcl
"${var.name_prefix}_${random_string.rs.id}"
```

This means:

```text
Take the value of var.name_prefix
add underscore
then add random_string.rs.id
```

---

## 11. Modern Terraform Syntax

In newer Terraform versions, simple variable usage does not always need `${}`.

Example:

```hcl
length = var.string_length
```

But when mixing text and values inside a string, interpolation is still useful:

```hcl
final_name = "${var.name_prefix}_${random_string.rs.id}"
```

You can also write it using `format()`:

```hcl
final_name = format("%s_%s", var.name_prefix, random_string.rs.id)
```

Both are valid.

---

## 12. Full Copy-Paste Demo Script

Use this to create the complete demo quickly:

```bash
mkdir -p ~/tf_random_placeholder && cd ~/tf_random_placeholder

cat > providers.tf <<'EOF_PROVIDER'
terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
EOF_PROVIDER

cat > variables.tf <<'EOF_VARIABLES'
variable "name_prefix" {
  description = "Prefix to add before the random string"
  type        = string
}

variable "string_length" {
  description = "Length of the random string"
  type        = number
  default     = 12
}
EOF_VARIABLES

cat > main.tf <<'EOF_MAIN'
resource "random_string" "rs" {
  special = false
  length  = var.string_length
}

locals {
  final_name = "${var.name_prefix}_${random_string.rs.id}"
}
EOF_MAIN

cat > outputs.tf <<'EOF_OUTPUTS'
output "random_string_id" {
  description = "Generated random string ID"
  value       = random_string.rs.id
}

output "final_name" {
  description = "Final name created using variable placeholder interpolation"
  value       = local.final_name
}
EOF_OUTPUTS

terraform init
terraform apply
```

---

## 13. Run Without Interactive Input

You can also pass variables directly from the command line:

```bash
terraform apply -var="name_prefix=robochef" -auto-approve
```

Example output:

```text
Outputs:

final_name = "robochef_aB91xYzLmKpQ"
random_string_id = "aB91xYzLmKpQ"
```

---

## 14. Change the Prefix

Run:

```bash
terraform apply -var="name_prefix=chillbot" -auto-approve
```

Terraform may update only the output value, because the random string resource already exists in state.

Example:

```text
final_name = "chillbot_TKDKdeuWzuJp"
```

---

## 15. Force a New Random String

To generate a new random string, destroy and apply again:

```bash
terraform destroy -var="name_prefix=robochef" -auto-approve
terraform apply -var="name_prefix=robochef" -auto-approve
```

Or remove the resource from Terraform state:

```bash
terraform state rm random_string.rs
terraform apply -var="name_prefix=robochef" -auto-approve
```

---

## 16. Clean Up

```bash
terraform destroy -var="name_prefix=robochef" -auto-approve
```

Since this demo only uses the random provider, no cloud resource is created.

Cleanup only removes the random string from Terraform state.

---

## Final Summary

| Concept | Example |
|---|---|
| Variable reference | `var.name_prefix` |
| Resource reference | `random_string.rs.id` |
| String interpolation | `"${var.name_prefix}_${random_string.rs.id}"` |
| Output reference | `local.final_name` |
| Provider used | `hashicorp/random` |
| Cloud required? | No |

Final generated name format:

```text
<prefix>_<random-string>
```

Example:

```text
robochef_TKDKdeuWzuJp
```
