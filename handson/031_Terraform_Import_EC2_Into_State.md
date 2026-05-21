# 031 — Terraform Import: Bring a Live EC2 into State

**By: Saravanan Sundaramoorthy**
**Environment:** AWS ap-south-1 (Mumbai)
**Time to complete:** ~15 minutes

---

## Topic

| Concept | What it means |
|---------|--------------|
| **`terraform import`** | Pulls an existing real-world resource into Terraform state without recreating it |
| **Unmanaged infrastructure** | Resources that exist in AWS but have no Terraform state entry |
| **Matching config** | You must write the `resource` block yourself — `terraform import` does NOT generate it |
| **The match problem** | After import, `terraform plan` must show 0 changes; any diff means your config doesn't match reality |
| **`terraform state`** | The `.tfstate` file that maps resource blocks to real AWS resource IDs |
| **`terraform plan -generate-config-out`** | Terraform 1.5+ feature that auto-generates a config file from an imported resource |
| **Import use cases** | Legacy infra, hand-built resources, resources created outside Terraform by another team |

---

## Flow Diagram

```
Step 1: Create EC2 manually (AWS CLI)
          |
          v
        EC2 instance exists in AWS
        i-0219ad944b37b13b0
        (NO Terraform state entry)
          |
Step 2: Write matching Terraform config (main.tf)
          |
          v
        resource "aws_instance" "imported" { ... }
        (config exists, state does NOT yet)
          |
Step 3: terraform init
          |
Step 4: terraform import aws_instance.imported i-0219ad944b37b13b0
          |
          v
        Terraform reads the live EC2 from AWS
        Writes it into terraform.tfstate
        "Import successful!"
          |
Step 5: terraform plan
          |
          v
        "No changes. Your infrastructure matches the configuration."
        (config matches state — the import worked)
          |
Step 6: terraform destroy (removes the EC2)
```

---

## What Happens Step by Step

| Step | What Terraform does | What AWS does |
|------|--------------------|--------------------|
| `terraform import` | Reads resource attributes from AWS API | No change — nothing is created or destroyed |
| Writes to state | Adds a new entry to `terraform.tfstate` | No change |
| `terraform plan` | Compares state to your config | No AWS API calls that mutate state |
| `terraform apply` | Only runs if plan shows a diff | Only if changes are needed |
| `terraform destroy` | Removes the resource from AWS and state | EC2 is terminated |

---

## Step 1 — Create the project folder

```bash
mkdir -p ~/terraform-aws-import-031-demo
cd ~/terraform-aws-import-031-demo
```

---

## Step 2 — Create an EC2 instance manually via AWS CLI

This simulates a hand-built resource — something that already exists in AWS with no Terraform state.

```bash
INSTANCE_ID=$(aws ec2 run-instances \
  --region ap-south-1 \
  --image-id ami-0a936bb624678fd88 \
  --instance-type t3.micro \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=terraform-031-imported},{Key=Owner,Value=saravanans},{Key=Project,Value=chillbotindia.com}]' \
  --no-associate-public-ip-address \
  --query 'Instances[0].InstanceId' --output text)

echo "Instance ID: $INSTANCE_ID"
```

Expected output:
```
Instance ID: i-0219ad944b37b13b0
```

Wait for the instance to reach the `running` state:

```bash
aws ec2 wait instance-running --instance-ids $INSTANCE_ID
echo "Instance is running."
```

Verify the instance exists with its tags:

```bash
aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query "Reservations[0].Instances[0].{ID:InstanceId,Type:InstanceType,State:State.Name,AZ:Placement.AvailabilityZone}" \
  --output table
```

Expected:
```
----------------------------------------------------------
|                    DescribeInstances                   |
+---------------------------+----+----------+------------+
|  i-0219ad944b37b13b0      | t3.micro | running | ap-south-1a |
+---------------------------+----+----------+------------+
```

At this point: **the EC2 exists in AWS, but Terraform knows nothing about it.**

---

## Step 3 — Write all Terraform files

### `providers.tf`

```bash
cat > providers.tf <<'EOF_TF'
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = var.aws_region
}
EOF_TF
```

### `variables.tf`

```bash
cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}
EOF_TF
```

### `main.tf`

This config is written to **match** the manually-created instance exactly.

```bash
cat > main.tf <<'EOF_TF'
# Look up the latest Ubuntu 22.04 AMI — matches what was used at instance creation
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_instance" "imported" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = ["sg-0186dc95c0247f346"]
  subnet_id              = "subnet-045bc71c853c3883f"

  tags = {
    Name    = "terraform-031-imported"
    Owner   = "saravanans"
    Project = "chillbotindia.com"
  }
}
EOF_TF
```

> Replace `sg-0186dc95c0247f346` and `subnet-045bc71c853c3883f` with the actual SG and subnet used when you created your instance. Find them with:
> ```bash
> aws ec2 describe-instances \
>   --instance-ids $INSTANCE_ID \
>   --query "Reservations[0].Instances[0].{SG:SecurityGroups[0].GroupId,Subnet:SubnetId}" \
>   --output table
> ```

### `outputs.tf`

```bash
cat > outputs.tf <<'EOF_TF'
output "instance_id" {
  description = "Imported EC2 instance ID"
  value       = aws_instance.imported.id
}

output "instance_state" {
  description = "Current state of the imported instance"
  value       = aws_instance.imported.instance_state
}

output "private_ip" {
  description = "Private IP of the imported instance"
  value       = aws_instance.imported.private_ip
}

output "instance_type" {
  description = "Instance type"
  value       = aws_instance.imported.instance_type
}
EOF_TF
```

---

## Step 4 — Init

```bash
terraform init
```

Expected output (key lines):
```
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Installing hashicorp/aws v6.x.x...

Terraform has been successfully initialized!
```

---

## Step 5 — Import the running EC2 into Terraform state

```bash
terraform import aws_instance.imported $INSTANCE_ID
```

Or if you no longer have the shell variable:

```bash
terraform import aws_instance.imported i-0219ad944b37b13b0
```

Expected output:
```
aws_instance.imported: Importing from ID "i-0219ad944b37b13b0"...
aws_instance.imported: Import prepared!
  Prepared aws_instance for import
aws_instance.imported: Refreshing state... [id=i-0219ad944b37b13b0]

Import successful!

The resources that were imported are shown above. These resources are now in
your Terraform state and will henceforth be managed by Terraform.
```

What just happened:
- Terraform called the AWS EC2 API and read all attributes of `i-0219ad944b37b13b0`
- It wrote those attributes into `terraform.tfstate`
- **Nothing was created or destroyed in AWS**

Inspect the state to confirm:

```bash
terraform state list
# aws_instance.imported

terraform state show aws_instance.imported | head -20
```

---

## Step 6 — Run terraform plan (expect 0 changes)

```bash
terraform plan
```

Expected output:
```
data.aws_ami.ubuntu: Reading...
data.aws_ami.ubuntu: Read complete after 1s [id=ami-0a936bb624678fd88]
aws_instance.imported: Refreshing state... [id=i-0219ad944b37b13b0]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
```

**This is the goal of a successful import.** If `terraform plan` shows changes (additions, updates, or replacements), your config does not match the real resource and you need to adjust `main.tf` until the plan is clean.

---

## Step 7 — Verify tags from AWS CLI

```bash
aws ec2 describe-tags \
  --filters "Name=resource-id,Values=$INSTANCE_ID" \
  --query "Tags[*].[Key,Value]" \
  --output table
```

Expected:
```
-------------------------------------
|           DescribeTags            |
+----------+------------------------+
|  Name    |  terraform-031-imported |
|  Owner   |  saravanans            |
|  Project |  chillbotindia.com     |
+----------+------------------------+
```

---

## Step 8 — Destroy

```bash
terraform destroy -auto-approve
rm -rf .terraform
```

Expected:
```
aws_instance.imported: Destroying... [id=i-0219ad944b37b13b0]
aws_instance.imported: Still destroying... [30s elapsed]
aws_instance.imported: Destruction complete after 35s

Destroy complete! Resources: 1 destroyed.
```

---

## Key Concept 1 — When to use `terraform import`

| Scenario | Use import? |
|----------|-------------|
| EC2 created manually in the console | Yes |
| S3 bucket created by another team | Yes |
| RDS created by a CloudFormation stack | Yes |
| Resource created by Terraform in another state file | Yes — use `terraform_remote_state` or import |
| Net-new resource not yet in AWS | No — just write the config and `terraform apply` |

Import is the bridge from **unmanaged** to **managed** infrastructure.

---

## Key Concept 2 — What `terraform import` does NOT do

`terraform import` writes to state. It does **not** write your config file.

```
What import DOES:             What import does NOT do:
- Reads the resource from AWS  - Write main.tf for you
- Populates terraform.tfstate  - Validate your config
- Maps ID → resource block     - Generate outputs.tf
                               - Run terraform apply
                               - Change anything in AWS
```

You must write (or have already written) the matching `resource` block before running `terraform import`. If the resource block doesn't exist in your config, import will fail with:

```
Error: resource address "aws_instance.imported" does not exist in the configuration.

Before importing this resource, please create its configuration in the root module.
```

---

## Key Concept 3 — The "match problem"

After a successful import, `terraform plan` must show **0 changes**. If the plan shows diffs, your config doesn't match the real resource.

**Common causes of a dirty plan after import:**

| Attribute | Problem | Fix |
|-----------|---------|-----|
| `ami` | Hardcoded old AMI vs. data source returning newer AMI | Use the exact AMI ID from the instance, not a dynamic lookup |
| `tags` | Missing or extra tags in config | Add/remove tags to match the instance exactly |
| `vpc_security_group_ids` | Wrong SG or wrong number of SGs | Use the exact SG IDs from the instance |
| `user_data` | Instance has user_data; config omits it | Add the user_data block or set it to `null` |
| `ebs_optimized` | Instance default differs from config | Remove the attribute and let Terraform use the default |

To debug: run `terraform plan` and read the diff. Each `~` (update) tells you which attribute differs.

---

## Key Concept 4 — Auto-generate config with `terraform plan -generate-config-out` (Terraform 1.5+)

Terraform 1.5 introduced a flag that writes a config file from an imported resource:

```bash
# First: add an empty import block to main.tf
cat >> main.tf <<'EOF_TF'

import {
  to = aws_instance.imported
  id = "i-0219ad944b37b13b0"
}
EOF_TF

# Then: generate the config
terraform plan -generate-config-out=generated.tf
```

Terraform writes `generated.tf` with all attributes filled in from the live resource. You can then review, clean up, and merge it into your `main.tf`. This eliminates most of the "match problem" since the generated config is derived directly from the real resource.

> `terraform plan -generate-config-out` requires Terraform >= 1.5 and the `import` block syntax (not the CLI command). The two approaches are complementary — use whichever fits your workflow.

---

## Concept Summary

| Concept | Key rule |
|---------|----------|
| `terraform import` | Adds an existing resource to state; does NOT create or destroy anything in AWS |
| Config required | You must write the `resource` block before running import |
| `terraform plan` after import | Must show 0 changes; any diff means config doesn't match reality |
| Match problem | Align every attribute (AMI, SGs, tags, etc.) with the real resource |
| `terraform state list` | Lists all resources currently in state |
| `terraform state show` | Prints all attributes of a specific resource in state |
| Import use case | Legacy infra, console-created resources, CloudFormation-managed resources |
| `-generate-config-out` | Terraform 1.5+ shortcut to auto-write the config from a live resource |
| `import {}` block | Declarative alternative to the `terraform import` CLI command (Terraform 1.5+) |
| After import, full lifecycle | Resource is now managed: plan, apply, destroy all work normally |

---

## Copy-paste script (full flow)

```bash
mkdir -p ~/terraform-aws-import-031-demo
cd ~/terraform-aws-import-031-demo

# Step 1: Create the EC2 manually
INSTANCE_ID=$(aws ec2 run-instances \
  --region ap-south-1 \
  --image-id ami-0a936bb624678fd88 \
  --instance-type t3.micro \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=terraform-031-imported},{Key=Owner,Value=saravanans},{Key=Project,Value=chillbotindia.com}]' \
  --no-associate-public-ip-address \
  --query 'Instances[0].InstanceId' --output text)
echo "Instance ID: $INSTANCE_ID"

aws ec2 wait instance-running --instance-ids $INSTANCE_ID
echo "Instance is running."

# Find the SG and subnet used
aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query "Reservations[0].Instances[0].{SG:SecurityGroups[0].GroupId,Subnet:SubnetId}" \
  --output table

# Step 2: Write Terraform files
cat > providers.tf <<'EOF_TF'
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = var.aws_region
}
EOF_TF

cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}
EOF_TF

cat > main.tf <<'EOF_TF'
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_instance" "imported" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = ["sg-0186dc95c0247f346"]
  subnet_id              = "subnet-045bc71c853c3883f"

  tags = {
    Name    = "terraform-031-imported"
    Owner   = "saravanans"
    Project = "chillbotindia.com"
  }
}
EOF_TF

cat > outputs.tf <<'EOF_TF'
output "instance_id" {
  description = "Imported EC2 instance ID"
  value       = aws_instance.imported.id
}

output "instance_state" {
  description = "Current state of the imported instance"
  value       = aws_instance.imported.instance_state
}

output "private_ip" {
  description = "Private IP of the imported instance"
  value       = aws_instance.imported.private_ip
}

output "instance_type" {
  description = "Instance type"
  value       = aws_instance.imported.instance_type
}
EOF_TF

# Step 3: Init
terraform init

# Step 4: Import
terraform import aws_instance.imported $INSTANCE_ID

# Step 5: Verify 0 changes
terraform plan

# Step 6: Verify tags via AWS CLI
aws ec2 describe-tags \
  --filters "Name=resource-id,Values=$INSTANCE_ID" \
  --query "Tags[*].[Key,Value]" \
  --output table

# Step 7: Destroy
terraform destroy -auto-approve
rm -rf .terraform
```
