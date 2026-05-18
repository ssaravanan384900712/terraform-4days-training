# Hands-On 4.4 — Terraform Testing

**File:** `~/lab4.4-testing/`

---

## Concept

Testing infrastructure code is fundamentally different from testing application code. You cannot mock AWS -- you must actually create resources and verify them. This lab covers the full testing pyramid for Terraform: manual inspection, native `terraform test`, Go-based integration tests with Terratest, and compliance scanning with tfsec and checkov.

### Testing Pyramid for Infrastructure

```
                    +-------------------+
                   /   End-to-End       /   Full environment deploy
                  /   (Expensive,      /    + smoke tests
                 /     slow)          /     Minutes to hours
                +-------------------+
               /   Integration       /   Create real resources
              /   (Terratest)       /    + validate + destroy
             /                     /     Minutes
            +-------------------+
           /   Unit Tests        /   terraform test (.tftest.hcl)
          /   (Plan-level)      /    No real resources (plan mode)
         /                     /     Seconds
        +-------------------+
       /   Static Analysis   /   tfsec, checkov, tflint
      /   (Fastest)         /    No Terraform execution
     /                     /     Seconds
    +-------------------+
   /   Manual Testing    /   terraform plan, console
  /   (Ad-hoc)          /    Developer workflow
 /                     /
+-------------------+
```

### Tool Comparison

| Tool | Type | Speed | Creates Resources | Language |
|------|------|-------|-------------------|----------|
| `terraform validate` | Syntax | Instant | No | N/A |
| `tfsec` | Static security | Seconds | No | N/A |
| `checkov` | Static compliance | Seconds | No | N/A |
| `terraform test` | Unit/Integration | Seconds-Minutes | Optional | HCL |
| Terratest | Integration | Minutes | Yes | Go |
| Manual `plan` | Inspection | Seconds | No | N/A |

---

## Part 1 — Manual Testing Basics

### Step 1: Plan Inspection

```bash
mkdir -p ~/lab4.4-testing/manual && cd ~/lab4.4-testing/manual
```

```hcl
# main.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "instance_type_map" {
  type = map(string)
  default = {
    dev     = "t3.micro"
    staging = "t3.small"
    prod    = "t3.medium"
  }
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.al2023.id
  instance_type = var.instance_type_map[var.environment]

  tags = {
    Name        = "web-${var.environment}"
    Environment = var.environment
  }
}

output "instance_type" {
  value = aws_instance.web.instance_type
}
```

```bash
terraform init

# Plan inspection -- see what WOULD happen
terraform plan -var='environment=dev'
terraform plan -var='environment=prod'

# Targeted apply -- only create specific resources
terraform apply -target=aws_instance.web -auto-approve
```

### Step 2: terraform console

```bash
# Interactive expression evaluation
terraform console

# Try these expressions:
> var.instance_type_map
{
  "dev" = "t3.micro"
  "staging" = "t3.small"
  "prod" = "t3.medium"
}

> var.instance_type_map["dev"]
"t3.micro"

> length(var.instance_type_map)
3

> [for k, v in var.instance_type_map : "${k} uses ${v}"]
[
  "dev uses t3.micro",
  "staging uses t3.small",
  "prod uses t3.medium",
]

> data.aws_ami.al2023.id
"ami-0abc123def456789"

> exit
```

---

## Part 2 — Manual Cleanup

### Destroy Patterns

```bash
# Destroy everything
terraform destroy -auto-approve

# Destroy specific resource only
terraform destroy -target=aws_instance.web -auto-approve

# Remove from state WITHOUT destroying the real resource
terraform state rm aws_instance.web
# The instance still exists in AWS but Terraform forgets about it

# List all resources in state
terraform state list

# Show details of a resource in state
terraform state show aws_instance.web

# Move a resource (rename in state)
terraform state mv aws_instance.web aws_instance.app

# Pull state to local file for inspection
terraform state pull > state-backup.json
```

---

## Part 3 — Unit Testing with terraform test

### Overview

`terraform test` (GA since Terraform 1.6) runs test files written in HCL. Tests can run in `plan` mode (no resources created) or `apply` mode (real resources).

### Step 3: Create a testable module

```bash
mkdir -p ~/lab4.4-testing/unit-test/{modules/tags,tests} && cd ~/lab4.4-testing/unit-test
```

```hcl
# modules/tags/variables.tf

variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "owner" {
  description = "Team or person who owns this resource"
  type        = string
  default     = "platform-team"
}

variable "extra_tags" {
  description = "Additional tags to merge"
  type        = map(string)
  default     = {}
}
```

```hcl
# modules/tags/main.tf

locals {
  standard_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
    CostCenter  = var.environment == "prod" ? "production" : "engineering"
  }

  all_tags = merge(local.standard_tags, var.extra_tags)
}
```

```hcl
# modules/tags/outputs.tf

output "standard_tags" {
  description = "Standard tags applied to all resources"
  value       = local.standard_tags
}

output "all_tags" {
  description = "All tags including extras"
  value       = local.all_tags
}

output "cost_center" {
  description = "Computed cost center"
  value       = local.standard_tags["CostCenter"]
}
```

### Step 4: Write test files

```hcl
# tests/tags_basic.tftest.hcl

# --- Test 1: Default tags are correct ---
run "default_tags" {
  command = plan    # No resources created

  module {
    source = "./modules/tags"
  }

  variables {
    project     = "myapp"
    environment = "dev"
  }

  # Assertions
  assert {
    condition     = output.standard_tags["Project"] == "myapp"
    error_message = "Project tag should be 'myapp'"
  }

  assert {
    condition     = output.standard_tags["Environment"] == "dev"
    error_message = "Environment tag should be 'dev'"
  }

  assert {
    condition     = output.standard_tags["ManagedBy"] == "terraform"
    error_message = "ManagedBy tag should be 'terraform'"
  }

  assert {
    condition     = output.standard_tags["Owner"] == "platform-team"
    error_message = "Default owner should be 'platform-team'"
  }
}

# --- Test 2: Cost center logic ---
run "cost_center_dev" {
  command = plan

  module {
    source = "./modules/tags"
  }

  variables {
    project     = "myapp"
    environment = "dev"
  }

  assert {
    condition     = output.cost_center == "engineering"
    error_message = "Dev cost center should be 'engineering'"
  }
}

run "cost_center_prod" {
  command = plan

  module {
    source = "./modules/tags"
  }

  variables {
    project     = "myapp"
    environment = "prod"
  }

  assert {
    condition     = output.cost_center == "production"
    error_message = "Prod cost center should be 'production'"
  }
}

# --- Test 3: Extra tags merge correctly ---
run "extra_tags_merge" {
  command = plan

  module {
    source = "./modules/tags"
  }

  variables {
    project     = "myapp"
    environment = "dev"
    extra_tags = {
      Application = "frontend"
      Team        = "web"
    }
  }

  assert {
    condition     = output.all_tags["Application"] == "frontend"
    error_message = "Extra tag 'Application' should be present"
  }

  assert {
    condition     = output.all_tags["ManagedBy"] == "terraform"
    error_message = "Standard tags should still be present after merge"
  }

  assert {
    condition     = length(output.all_tags) == 7
    error_message = "Should have 5 standard + 2 extra = 7 tags"
  }
}
```

```hcl
# tests/tags_validation.tftest.hcl

# --- Test 4: Invalid environment should fail ---
run "invalid_environment" {
  command = plan

  module {
    source = "./modules/tags"
  }

  variables {
    project     = "myapp"
    environment = "invalid"    # Not in allowed list
  }

  # Expect this to FAIL validation
  expect_failures = [
    var.environment
  ]
}
```

### Step 5: Run the tests

```bash
cd ~/lab4.4-testing/unit-test

terraform init
terraform test
```

Expected output:
```
tests/tags_basic.tftest.hcl... in progress
  run "default_tags"... pass
  run "cost_center_dev"... pass
  run "cost_center_prod"... pass
  run "extra_tags_merge"... pass
tests/tags_basic.tftest.hcl... tearing down
tests/tags_basic.tftest.hcl... pass

tests/tags_validation.tftest.hcl... in progress
  run "invalid_environment"... pass
tests/tags_validation.tftest.hcl... tearing down
tests/tags_validation.tftest.hcl... pass

Success! 5 passed, 0 failed.
```

```bash
# Verbose output
terraform test -verbose

# Run a specific test file
terraform test -filter=tests/tags_basic.tftest.hcl
```

---

## Part 4 — Integration Testing with Terratest

Terratest is a Go library that creates real AWS resources, validates them, and destroys them.

### Step 6: Create a module to test

```bash
mkdir -p ~/lab4.4-testing/terratest-demo/{modules/web-server,test} && cd ~/lab4.4-testing/terratest-demo
```

```hcl
# modules/web-server/main.tf

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "server_text" {
  type    = string
  default = "Hello from Terratest"
}

provider "aws" {
  region = "us-east-1"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.al2023.id
  instance_type = var.instance_type

  user_data = <<-EOF
    #!/bin/bash
    yum install -y httpd
    echo '${var.server_text}' > /var/www/html/index.html
    systemctl start httpd
  EOF

  vpc_security_group_ids = [aws_security_group.web.id]

  tags = {
    Name = "terratest-web"
  }
}

resource "aws_security_group" "web" {
  name_prefix = "terratest-"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "public_ip" {
  value = aws_instance.web.public_ip
}

output "instance_id" {
  value = aws_instance.web.id
}
```

### Step 7: Write the Go test

```go
// test/web_server_test.go

package test

import (
	"fmt"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestWebServer(t *testing.T) {
	t.Parallel()

	expectedServerText := "Hello from Terratest"

	// Configure Terraform options
	terraformOptions := &terraform.Options{
		// Path to the module
		TerraformDir: "../modules/web-server",

		// Variables to pass
		Vars: map[string]interface{}{
			"instance_type": "t3.micro",
			"server_text":   expectedServerText,
		},

		// Retry on known transient errors
		RetryableTerraformErrors: map[string]string{
			"RequestError: send request failed": "Transient AWS API error",
		},
		MaxRetries:         3,
		TimeBetweenRetries: 5 * time.Second,
	}

	// Clean up resources when test completes
	defer terraform.Destroy(t, terraformOptions)

	// Deploy the infrastructure
	terraform.InitAndApply(t, terraformOptions)

	// Get outputs
	publicIP := terraform.Output(t, terraformOptions, "public_ip")
	instanceID := terraform.Output(t, terraformOptions, "instance_id")

	// Validate outputs are not empty
	assert.NotEmpty(t, publicIP, "Public IP should not be empty")
	assert.NotEmpty(t, instanceID, "Instance ID should not be empty")
	assert.Contains(t, instanceID, "i-", "Instance ID should start with 'i-'")

	// Wait for the web server to boot and respond
	url := fmt.Sprintf("http://%s", publicIP)
	maxRetries := 30
	timeBetweenRetries := 10 * time.Second

	// HTTP health check
	http_helper.HttpGetWithRetry(
		t,
		url,
		nil,                   // TLS config
		200,                   // expected status
		expectedServerText,    // expected body
		maxRetries,
		timeBetweenRetries,
	)
}
```

```bash
# Initialize Go module and install dependencies
cd ~/lab4.4-testing/terratest-demo/test

go mod init github.com/myorg/terratest-demo
go mod tidy

# Run the test (takes 3-5 minutes)
go test -v -timeout 15m

# Expected output:
# === RUN   TestWebServer
# TestWebServer 2026-05-18T10:00:00Z ... Running command terraform init
# TestWebServer 2026-05-18T10:00:05Z ... Running command terraform apply
# TestWebServer 2026-05-18T10:01:30Z ... public_ip = "54.xx.xx.xx"
# TestWebServer 2026-05-18T10:01:30Z ... Making HTTP GET call to http://54.xx.xx.xx
# TestWebServer 2026-05-18T10:02:00Z ... Got expected response
# TestWebServer 2026-05-18T10:02:00Z ... Running command terraform destroy
# --- PASS: TestWebServer (180.00s)
# PASS
```

---

## Part 5 — Static Analysis with tfsec

### Step 8: Install and run tfsec

```bash
# Install tfsec
curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash

# Or via Go
go install github.com/aquasecurity/tfsec/cmd/tfsec@latest
```

Create a file with intentional security issues:

```bash
mkdir -p ~/lab4.4-testing/tfsec-demo && cd ~/lab4.4-testing/tfsec-demo
```

```hcl
# main.tf -- Intentionally insecure for testing

provider "aws" {
  region = "us-east-1"
}

resource "aws_security_group" "bad_sg" {
  name = "wide-open-sg"

  # tfsec will flag: unrestricted ingress
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_s3_bucket" "bad_bucket" {
  bucket = "my-insecure-bucket"
}

# tfsec will flag: no encryption, no versioning, no public access block

resource "aws_instance" "no_metadata" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"

  # tfsec will flag: no IMDSv2 requirement
}
```

```bash
tfsec .
```

Expected output:
```
Result #1 CRITICAL Security group rule allows unrestricted ingress
  ──────────────────────────────────────────────────────
  main.tf:10-16

Result #2 HIGH S3 bucket does not have encryption enabled
  ──────────────────────────────────────────────────────
  main.tf:19-21

Result #3 MEDIUM S3 bucket does not have versioning enabled
  ──────────────────────────────────────────────────────
  main.tf:19-21

Result #4 HIGH EC2 instance does not require IMDSv2
  ──────────────────────────────────────────────────────
  main.tf:25-28

  4 potential problem(s) detected.
```

```bash
# Output as JUnit for CI/CD
tfsec . --format junit > tfsec-results.xml

# Fail CI if issues found
tfsec . --minimum-severity HIGH
echo $?    # Non-zero = findings exist

# Exclude specific checks
tfsec . --exclude aws-s3-enable-versioning
```

---

## Part 6 — Compliance Scanning with checkov

### Step 9: Install and run checkov

```bash
pip install checkov

cd ~/lab4.4-testing/tfsec-demo    # Reuse the insecure config
```

```bash
checkov -d .
```

Expected output:
```
       _               _
   ___| |__   ___  ___| | _______   __
  / __| '_ \ / _ \/ __| |/ / _ \ \ / /
 | (__| | | |  __/ (__|   < (_) \ V /
  \___|_| |_|\___|\___|_|\_\___/ \_/

Passed checks: 1, Failed checks: 7, Skipped checks: 0

Check: CKV_AWS_260: "Ensure no security group allows ingress from 0.0.0.0/0 to all ports"
	FAILED for resource: aws_security_group.bad_sg
	File: main.tf:6-17

Check: CKV_AWS_145: "Ensure S3 bucket is encrypted with KMS"
	FAILED for resource: aws_s3_bucket.bad_bucket
	File: main.tf:19-21

Check: CKV_AWS_21: "Ensure S3 bucket has versioning enabled"
	FAILED for resource: aws_s3_bucket.bad_bucket
	File: main.tf:19-21

Check: CKV_AWS_18: "Ensure S3 bucket has access logging enabled"
	FAILED for resource: aws_s3_bucket.bad_bucket
	File: main.tf:19-21

Check: CKV2_AWS_6: "Ensure S3 bucket has a Public Access Block"
	FAILED for resource: aws_s3_bucket.bad_bucket
	File: main.tf:19-21

Check: CKV_AWS_79: "Ensure Instance Metadata Service Version 1 is not enabled"
	FAILED for resource: aws_instance.no_metadata
	File: main.tf:25-28

Check: CKV_AWS_8: "Ensure all data stored in the Launch configuration EBS is encrypted"
	FAILED for resource: aws_instance.no_metadata
	File: main.tf:25-28
```

```bash
# Output as JSON for processing
checkov -d . -o json > checkov-results.json

# Check specific framework
checkov -d . --framework terraform

# Skip specific checks
checkov -d . --skip-check CKV_AWS_21,CKV_AWS_18

# Use a custom policy config
checkov -d . --config-file .checkov.yaml
```

### checkov config file

```yaml
# .checkov.yaml

soft-fail: false
framework:
  - terraform
skip-check:
  - CKV_AWS_18    # S3 access logging (not needed for state bucket)
compact: true
output:
  - cli
  - junitxml
```

---

## Part 7 — Drift Detection with Plan Exit Code

```bash
# -detailed-exitcode returns:
#   0 = no changes
#   1 = error
#   2 = changes detected (drift!)

terraform plan -detailed-exitcode
EXIT_CODE=$?

if [ $EXIT_CODE -eq 2 ]; then
  echo "DRIFT DETECTED! Infrastructure has changed outside Terraform."
  # Send alert, open ticket, etc.
elif [ $EXIT_CODE -eq 0 ]; then
  echo "No drift. Infrastructure matches state."
else
  echo "Error running plan."
fi
```

### CI/CD Drift Detection Job

```yaml
# .github/workflows/drift-detection.yml

name: Drift Detection
on:
  schedule:
    - cron: '0 8 * * 1-5'    # Weekdays at 8 AM

jobs:
  drift-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: terraform init

      - name: Check for Drift
        id: plan
        run: terraform plan -detailed-exitcode
        continue-on-error: true

      - name: Alert on Drift
        if: steps.plan.outcome == 'failure'
        run: |
          echo "::warning::Infrastructure drift detected!"
          # Could send Slack notification, create Jira ticket, etc.
```

---

## Full Test Pipeline Summary

```
  git push
     |
     v
  +------------------+
  | terraform fmt    |  <-- Pre-commit hook
  | terraform validate|
  +--------+---------+
           |
           v
  +------------------+
  | tfsec            |  <-- Static security scan
  | checkov          |
  +--------+---------+
           |
           v
  +------------------+
  | terraform test   |  <-- Unit tests (plan mode)
  | (.tftest.hcl)    |
  +--------+---------+
           |
           v
  +------------------+
  | Terratest        |  <-- Integration tests (real resources)
  | (Go tests)       |
  +--------+---------+
           |
           v
  +------------------+
  | terraform plan   |  <-- Final plan review
  | -detailed-exitcode|
  +------------------+
```

---

## Summary

| Testing Layer | Tool | Creates Resources | Speed | When to Use |
|--------------|------|-------------------|-------|-------------|
| Format/Syntax | `fmt`, `validate` | No | Instant | Every commit |
| Security | tfsec | No | Seconds | Every commit |
| Compliance | checkov | No | Seconds | Every commit |
| Unit | `terraform test` (plan) | No | Seconds | Every PR |
| Unit | `terraform test` (apply) | Yes | Minutes | Nightly |
| Integration | Terratest | Yes | Minutes | Before release |
| Drift | `plan -detailed-exitcode` | No | Seconds | Scheduled |
