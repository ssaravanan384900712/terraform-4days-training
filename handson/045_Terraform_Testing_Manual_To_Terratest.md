# 045 — Terraform Testing: Manual to Terratest

**By:** Saravanan Sundaramoorthy
**Environment:** Local
**Time:** ~20 min

---

## Overview

Infrastructure that is never tested is infrastructure that will eventually break in production. This lab walks through the full testing spectrum for Terraform: manual CLI-based testing, the built-in `terraform test` framework (Terraform 1.6+), and Terratest — a Go-based framework for full integration tests. You will use the `local` provider throughout so no cloud credentials are needed.

---

## Prerequisites

- Terraform 1.6+ (`terraform version`)
- Go 1.21+ for the Terratest section (`go version`)
- `jq` for plan inspection (`jq --version`)

---

## 1. Manual Testing Basics

Manual testing means using Terraform CLI flags to control and inspect what your configuration will do, before and after applying.

### Save and inspect a plan

```bash
# Save the plan to a binary file — this exact plan will be applied, no re-evaluation
terraform plan -out=plan.tfplan

# Inspect the saved plan in human-readable form
terraform show plan.tfplan

# Inspect as JSON (useful for scripting and CI assertions)
terraform show -json plan.tfplan | jq .

# Apply the saved plan exactly — no prompts, no re-plan
terraform apply plan.tfplan
```

The key benefit of `plan -out` is determinism: the apply step runs the exact same plan that was reviewed. No drift between `plan` and `apply`.

### Inspecting plan JSON

```bash
# List all resources that will be created
terraform show -json plan.tfplan | jq '[.resource_changes[] | select(.change.actions == ["create"]) | .address]'

# List all resources that will be destroyed
terraform show -json plan.tfplan | jq '[.resource_changes[] | select(.change.actions | contains(["delete"])) | .address]'

# Show planned values for a specific resource
terraform show -json plan.tfplan | jq '.resource_changes[] | select(.address == "local_file.config") | .change.after'
```

### Targeted plan and apply

When you only want to affect a single resource during development:

```bash
# Plan changes to one resource only
terraform plan -target=local_file.config

# Apply changes to one resource only
terraform apply -target=local_file.config
```

Use `-target` sparingly — it bypasses dependency checking and can leave your configuration in an inconsistent state. Never use it in production as a workaround for design problems.

### Force-replace a specific resource

When a resource is misbehaving and you need to recreate it without changing any code:

```bash
terraform apply -replace=local_file.config
```

This is equivalent to manually running `terraform state rm` then `terraform apply`, but safer because it does everything in one atomic plan-then-apply.

### Validate configuration syntax

```bash
# Check for syntax errors and invalid references (fast, no API calls)
terraform validate

# Format all .tf files in the current directory
terraform fmt

# Check formatting without modifying files (useful in CI)
terraform fmt -check
```

### Checking outputs

```bash
# Show all outputs
terraform output

# Show a specific output value only (useful in scripts)
terraform output config_file

# Get output as JSON (no formatting, safe for piping)
terraform output -json config_files | jq '.[]'
```

---

## 2. terraform test — Built-in Testing (Terraform 1.6+)

Terraform 1.6 introduced a built-in test framework that runs `.tftest.hcl` files. Tests live in a `tests/` directory alongside your configuration and can run `apply` or `plan` operations with assertions.

### Project setup

Create the working directory:

```bash
mkdir -p /tmp/tf-test-lab/tests
cd /tmp/tf-test-lab
```

Create `main.tf`:

```hcl
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

variable "site_name" {
  type        = string
  default     = "robochef"
  description = "Name of the site being configured"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Deployment environment"
}

locals {
  config_path    = "/tmp/${var.site_name}-config.txt"
  site_domain    = "${var.site_name}.co"
  content_lines  = [
    "site=${local.site_domain}",
    "environment=${var.environment}",
    "owner=saravanans",
  ]
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "local_file" "config" {
  filename        = local.config_path
  content         = join("\n", local.content_lines)
  file_permission = "0644"
}

output "config_file" {
  value = local_file.config.filename
}

output "site_domain" {
  value = local.site_domain
}

output "suffix" {
  value = random_id.suffix.hex
}
```

### Writing test files

Create `tests/basic.tftest.hcl`:

```hcl
# tests/basic.tftest.hcl

# Override variables for the test run
variables {
  site_name   = "robochef"
  environment = "test"
}

# run blocks are executed in order
run "create_config_file" {
  command = apply   # actually creates infrastructure

  assert {
    condition     = local_file.config.filename == "/tmp/robochef-config.txt"
    error_message = "Expected filename /tmp/robochef-config.txt, got: ${local_file.config.filename}"
  }

  assert {
    condition     = fileexists("/tmp/robochef-config.txt")
    error_message = "Config file was not created on disk"
  }

  assert {
    condition     = local_file.config.file_permission == "0644"
    error_message = "Expected file permission 0644"
  }
}

run "check_output_values" {
  command = plan   # plan only, no real changes

  assert {
    condition     = output.site_domain == "robochef.co"
    error_message = "Expected site_domain to be robochef.co"
  }

  assert {
    condition     = output.config_file == "/tmp/robochef-config.txt"
    error_message = "config_file output has wrong value"
  }
}

run "check_content" {
  command = plan

  assert {
    condition     = contains(split("\n", local_file.config.content), "site=robochef.co")
    error_message = "Content missing 'site=robochef.co' line"
  }

  assert {
    condition     = contains(split("\n", local_file.config.content), "environment=test")
    error_message = "Content missing 'environment=test' line"
  }

  assert {
    condition     = contains(split("\n", local_file.config.content), "owner=saravanans")
    error_message = "Content missing 'owner=saravanans' line"
  }
}
```

### Running the tests

```bash
terraform init
terraform test
```

Expected output:

```
tests/basic.tftest.hcl... in progress
  run "create_config_file"... pass
  run "check_output_values"... pass
  run "check_content"... pass
tests/basic.tftest.hcl... tearing down
tests/basic.tftest.hcl... pass

Success! 3 passed, 0 failed.
```

Terraform automatically destroys all resources created during `apply` runs when the test completes. This is why `terraform test` is safe to run repeatedly.

### Testing with different variable sets

You can have multiple `.tftest.hcl` files, each testing a different scenario:

```bash
# Run all test files
terraform test

# Run a specific test file
terraform test -filter=tests/basic.tftest.hcl

# Run in verbose mode to see each assertion
terraform test -verbose
```

Create `tests/prod_scenario.tftest.hcl`:

```hcl
# tests/prod_scenario.tftest.hcl

variables {
  site_name   = "robotea"
  environment = "prod"
}

run "prod_config_file" {
  command = apply

  assert {
    condition     = local_file.config.filename == "/tmp/robotea-config.txt"
    error_message = "Expected /tmp/robotea-config.txt"
  }

  assert {
    condition     = contains(split("\n", local_file.config.content), "environment=prod")
    error_message = "Prod config missing correct environment"
  }
}
```

```bash
terraform test
# Runs both basic.tftest.hcl and prod_scenario.tftest.hcl
```

---

## 3. Terratest — Go-Based Integration Testing

Terratest is a Go library from Gruntwork that applies real Terraform configurations, runs assertions against real infrastructure (or real local resources), and destroys everything afterwards. It is the standard for module-level integration testing.

### When to use Terratest vs terraform test

| Scenario | Use |
|----------|-----|
| Assert on Terraform outputs and state | `terraform test` |
| Assert on actual files, HTTP endpoints, DNS, or API responses | Terratest |
| Test Terraform modules in isolation | Either |
| Test full environment with external verification | Terratest |
| CI pipeline (fast feedback) | `terraform test` |
| Module release gate (thorough) | Terratest |

### Project structure

```
terraform-module/
├── main.tf
├── variables.tf
├── outputs.tf
└── test/
    ├── go.mod
    ├── go.sum
    └── module_test.go
```

### The Terraform module under test

Create this structure:

```bash
mkdir -p /tmp/tf-terratest-lab/test
cd /tmp/tf-terratest-lab
```

`main.tf`:

```hcl
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

variable "site_name" {
  type        = string
  description = "Name of the site"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Deployment environment"
}

locals {
  config_path = "/tmp/${var.site_name}-${var.environment}-config.txt"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "local_file" "config" {
  filename = local.config_path
  content  = "site=${var.site_name}.co\nenvironment=${var.environment}\nsuffix=${random_id.suffix.hex}"
}

output "config_file" {
  value = local_file.config.filename
}

output "suffix" {
  value = random_id.suffix.hex
}
```

### The Terratest Go test file

`test/module_test.go`:

```go
package test

import (
    "os"
    "strings"
    "testing"

    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
)

// TestTerraformLocalFile tests the local_file module end-to-end.
// It applies the Terraform configuration, verifies outputs and actual file
// contents, then destroys everything.
func TestTerraformLocalFile(t *testing.T) {
    t.Parallel()

    opts := &terraform.Options{
        // Path to the Terraform module under test
        TerraformDir: "../",

        // Variable values to pass in — equivalent to -var flags
        Vars: map[string]interface{}{
            "site_name":   "robochef",
            "environment": "test",
        },
    }

    // Destroy all resources at the end of the test, even if it fails
    defer terraform.Destroy(t, opts)

    // Run terraform init and terraform apply
    terraform.InitAndApply(t, opts)

    // --- Assert on Terraform outputs ---

    configFile := terraform.Output(t, opts, "config_file")
    assert.Equal(t, "/tmp/robochef-test-config.txt", configFile,
        "config_file output should match expected path")

    suffix := terraform.Output(t, opts, "suffix")
    assert.NotEmpty(t, suffix, "suffix output should not be empty")
    assert.Len(t, suffix, 8, "suffix should be 8 hex characters (4 bytes)")

    // --- Assert on actual file system ---

    require.FileExists(t, configFile, "Config file should exist on disk")

    content, err := os.ReadFile(configFile)
    require.NoError(t, err, "Should be able to read the config file")

    contentStr := string(content)
    assert.True(t, strings.Contains(contentStr, "site=robochef.co"),
        "File content should contain site=robochef.co")
    assert.True(t, strings.Contains(contentStr, "environment=test"),
        "File content should contain environment=test")
    assert.True(t, strings.Contains(contentStr, "suffix="+suffix),
        "File content should contain the suffix from the output")
}

// TestTerraformLocalFileMultipleEnvironments verifies that the same module
// can be deployed with different variable sets without conflict.
func TestTerraformLocalFileMultipleEnvironments(t *testing.T) {
    environments := []struct {
        name     string
        siteName string
        env      string
    }{
        {"dev", "robochef", "dev"},
        {"prod", "robotea", "prod"},
    }

    for _, tc := range environments {
        tc := tc // capture range variable

        t.Run(tc.name, func(t *testing.T) {
            t.Parallel()

            opts := &terraform.Options{
                TerraformDir: "../",
                Vars: map[string]interface{}{
                    "site_name":   tc.siteName,
                    "environment": tc.env,
                },
            }

            defer terraform.Destroy(t, opts)
            terraform.InitAndApply(t, opts)

            configFile := terraform.Output(t, opts, "config_file")
            expectedPath := "/tmp/" + tc.siteName + "-" + tc.env + "-config.txt"
            assert.Equal(t, expectedPath, configFile)

            require.FileExists(t, configFile)
        })
    }
}
```

### Setting up the Go module

```bash
cd /tmp/tf-terratest-lab/test

# Initialize a Go module
go mod init terraform-test

# Add Terratest as a dependency
go get github.com/gruntwork-io/terratest/modules/terraform
go get github.com/stretchr/testify/assert
go get github.com/stretchr/testify/require

# Tidy dependencies
go mod tidy
```

### Running Terratest

```bash
# Run all tests (with a timeout — Terratest applies real infrastructure)
go test ./test/ -v -timeout 30m

# Run a specific test function
go test ./test/ -v -timeout 30m -run TestTerraformLocalFile

# Run with verbose Terraform output
go test ./test/ -v -timeout 30m -run TestTerraformLocalFile 2>&1 | tee test-output.txt
```

Expected output:

```
=== RUN   TestTerraformLocalFile
--- PASS: TestTerraformLocalFile (3.21s)
=== RUN   TestTerraformLocalFileMultipleEnvironments
=== RUN   TestTerraformLocalFileMultipleEnvironments/dev
=== RUN   TestTerraformLocalFileMultipleEnvironments/prod
--- PASS: TestTerraformLocalFileMultipleEnvironments (4.05s)
PASS
ok      terraform-test  7.26s
```

### Key Terratest patterns

**Retry on eventual consistency:**
```go
import "github.com/gruntwork-io/terratest/modules/retry"

// Retry up to 10 times with 5-second intervals
retry.DoWithRetry(t, "Wait for resource to be ready", 10, 5*time.Second, func() (string, error) {
    // check something
    return "", nil
})
```

**HTTP endpoint testing (for AWS resources):**
```go
import "github.com/gruntwork-io/terratest/modules/http-helper"

url := terraform.Output(t, opts, "endpoint_url")
http_helper.HttpGetWithRetry(t, url, nil, 200, "OK", 30, 5*time.Second)
```

**SSH into an EC2 instance:**
```go
import "github.com/gruntwork-io/terratest/modules/ssh"

publicIP := terraform.Output(t, opts, "public_ip")
host := ssh.Host{
    Hostname:    publicIP,
    SshUserName: "ubuntu",
    SshKeyPair:  keyPair,
}
output, err := ssh.CheckSshCommand(t, host, "uptime")
assert.NoError(t, err)
assert.Contains(t, output, "load average")
```

---

## 4. Testing Pyramid for Terraform

| Layer | Tool | What It Tests | Speed | Cost |
|-------|------|--------------|-------|------|
| Static analysis | `terraform validate`, `tflint` | Syntax, types, lint rules | Seconds | Free |
| Unit | `terraform test` (plan runs) | Logic, expressions, variable defaults | Seconds | Free |
| Integration | `terraform test` (apply runs) | Resource creation, outputs, state | Seconds–minutes | Free (local provider) / Low (cloud) |
| End-to-end | Terratest | Real infrastructure + external verification | Minutes | Cloud costs |
| Acceptance | Full env + smoke tests | Full user journey | Minutes–hours | $$ |

### Recommended CI pipeline

```yaml
# Example: GitHub Actions pipeline stages

validate:
  steps:
    - run: terraform fmt -check
    - run: terraform validate
    - run: tflint

unit-test:
  steps:
    - run: terraform test -filter=tests/unit/

integration-test:
  steps:
    - run: terraform test           # all .tftest.hcl files
  if: github.event_name == 'pull_request'

e2e-test:
  steps:
    - run: go test ./test/ -v -timeout 60m
  if: github.ref == 'refs/heads/main'
```

### When to run each layer

- **Every commit:** `validate`, `fmt -check`, `terraform test` (plan-only runs)
- **Every PR:** Full `terraform test` (apply runs against local or sandbox environment)
- **Before release:** Terratest against real cloud (dev account, not production)
- **Never in production directly:** Infrastructure tests create and destroy real resources

---

## 5. Cleanup

```bash
# terraform test cleans up automatically after each test run.
# For manual cleanup of the exercise directories:
rm -rf /tmp/tf-test-lab
rm -rf /tmp/tf-terratest-lab

# In any Terraform directory you initialized manually:
terraform destroy -auto-approve
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
```

---

## Summary

| Tool | Best For | Terraform Version |
|------|----------|-------------------|
| `terraform plan -out` | Deterministic apply, CI pipelines | All versions |
| `terraform validate` | Syntax and type checking | All versions |
| `terraform test` | Unit and integration assertions in HCL | 1.6+ |
| Terratest | Full end-to-end with external verification | Any (Go wrapper) |
| `terraform apply -replace` | Force-recreate one resource without code changes | 0.15+ |
| `terraform plan -target` | Scoped testing during development | All versions |

The ideal approach: use `terraform test` for everything you can express in HCL assertions, and reach for Terratest only when you need to verify something outside Terraform's state — HTTP endpoints, database connectivity, file contents, DNS resolution.
