# Hands-On 3.2 --- Data Sources Deep Dive

**File:** `data.tf`, `main.tf`, `scripts/get_latest_tag.sh`

---

## Concept

A **data source** lets Terraform **read** information from the provider without creating or managing the resource. Think of it as a SELECT query: you ask the provider "what exists?" and use the answer in your own resources.

```
+-----------------------+           +-------------------+
|   Terraform Config    |           |   AWS Account     |
|                       |           |                   |
|  data "aws_vpc" {     |  ----->   |   Existing VPC    |
|    filter { ... }     |  Query    |   id = vpc-abc123 |
|  }                    |  <-----   |   cidr = 10.0.0/16|
|                       |  Result   |                   |
|  resource "aws_sub.." |           |                   |
|    vpc_id = data...id |           |   New Subnet      |
|                       |           |   (created by TF) |
+-----------------------+           +-------------------+
```

### Data Source vs Resource

| Aspect | `resource` | `data` |
|--------|-----------|--------|
| Purpose | Create/manage infrastructure | Read existing infrastructure |
| Lifecycle | Create, update, destroy | Read-only, refreshed each plan |
| State | Stored in state file | Stored in state (read-only) |
| Changes | You control the changes | Provider controls the data |
| Syntax | `resource "type" "name"` | `data "type" "name"` |

---

## 1. Data Source Refresh Behavior

Data sources are read during **every** `terraform plan` and `terraform apply`. They always reflect the current state of the provider.

```
terraform plan
    |
    v
Read all data sources -----> Query AWS API
    |                           |
    v                           v
Compare resources       Return current values
    |
    v
Generate plan
```

> **Warning:** If an external resource changes between `plan` and `apply`, the data source will re-read during apply. This can occasionally cause plan drift.

---

## 2. Querying Existing Resources

### 2.1 Look Up the Default VPC

```hcl
# data.tf

data "aws_vpc" "default" {
  default = true
}

output "default_vpc_id" {
  value = data.aws_vpc.default.id
}

output "default_vpc_cidr" {
  value = data.aws_vpc.default.cidr_block
}
```

```bash
$ terraform init && terraform apply -auto-approve

Outputs:

default_vpc_id   = "vpc-0a1b2c3d4e5f"
default_vpc_cidr = "172.31.0.0/16"
```

### 2.2 Look Up a VPC by Tag

```hcl
data "aws_vpc" "production" {
  filter {
    name   = "tag:Environment"
    values = ["production"]
  }
}

output "prod_vpc_cidr" {
  value = data.aws_vpc.production.cidr_block
}
```

### 2.3 Look Up Subnets in a VPC

```hcl
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

output "public_subnet_ids" {
  value = data.aws_subnets.public.ids
}
```

---

## 3. AMI Lookup

One of the most common data sources: find the latest Amazon Linux 2023 AMI dynamically instead of hard-coding an AMI ID.

```hcl
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

output "latest_ami_id" {
  value = data.aws_ami.amazon_linux.id
}

output "latest_ami_name" {
  value = data.aws_ami.amazon_linux.name
}

# Use it in an instance
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  tags = {
    Name = "web-from-data-source"
  }
}
```

```bash
$ terraform plan

  + resource "aws_instance" "web" {
      + ami           = "ami-0abcdef1234567890"
      + instance_type = "t3.micro"
    }
```

> **Tip:** Using `most_recent = true` with filters is the standard pattern. Never hard-code AMI IDs --- they differ by region and get deprecated.

---

## 4. Availability Zones

Dynamically discover all AZs in the current region:

```hcl
data "aws_availability_zones" "available" {
  state = "available"

  # Exclude Local Zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

output "az_names" {
  value = data.aws_availability_zones.available.names
}

output "az_count" {
  value = length(data.aws_availability_zones.available.names)
}
```

### Using AZs to Spread Subnets

```hcl
resource "aws_subnet" "private" {
  count             = length(data.aws_availability_zones.available.names)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "private-${data.aws_availability_zones.available.names[count.index]}"
  }
}
```

```
Result in us-east-1:

  Subnet 0: 10.0.0.0/24  in us-east-1a
  Subnet 1: 10.0.1.0/24  in us-east-1b
  Subnet 2: 10.0.2.0/24  in us-east-1c
  Subnet 3: 10.0.3.0/24  in us-east-1d
  Subnet 4: 10.0.4.0/24  in us-east-1e
  Subnet 5: 10.0.5.0/24  in us-east-1f
```

---

## 5. AWS Caller Identity and Region

Useful for constructing ARNs and ensuring you are in the right account:

```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  value = data.aws_caller_identity.current.arn
}

output "current_region" {
  value = data.aws_region.current.name
}

# Practical use: construct an S3 bucket ARN
locals {
  bucket_arn = "arn:aws:s3:::${data.aws_caller_identity.current.account_id}-logs"
}
```

---

## 6. Local-Only Data Sources

Some data sources do not call any API. They compute values locally.

### 6.1 Template Rendering

```hcl
# user_data.sh.tpl
# #!/bin/bash
# echo "Hello from ${server_name}"
# yum install -y ${packages}

data "template_file" "user_data" {
  template = file("${path.module}/user_data.sh.tpl")

  vars = {
    server_name = "web-01"
    packages    = "httpd php mysql"
  }
}

# Modern alternative: templatefile() function (preferred)
locals {
  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    server_name = "web-01"
    packages    = "httpd php mysql"
  })
}
```

> **Tip:** The `template_file` data source is deprecated. Use the `templatefile()` function instead. We show both so you recognize legacy code.

### 6.2 Local File

```hcl
data "local_file" "ssh_key" {
  filename = "${path.module}/keys/deploy.pub"
}

resource "aws_key_pair" "deploy" {
  key_name   = "deploy-key"
  public_key = data.local_file.ssh_key.content
}
```

---

## 7. External Data Source

The `external` data source runs an arbitrary program and reads its JSON output. Useful for integrating with scripts or APIs that Terraform does not natively support.

```
Terraform                    External Script
   |                              |
   |--- stdin (JSON query) -----> |
   |                              | (run logic)
   |<-- stdout (JSON result) --- |
   |                              |
```

### Requirements

1. The script must read JSON from stdin
2. The script must write JSON to stdout
3. All values in the JSON must be strings
4. The script must exit 0 on success

### Hands-On: Bash Script Data Source

**scripts/get_latest_tag.sh:**

```bash
#!/bin/bash
# Read input JSON (optional query parameters)
eval "$(jq -r '@sh "REPO=\(.repo)"')"

# Simulate fetching the latest git tag
# In real use, this might call an API
LATEST_TAG=$(git -C "$REPO" describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")

# Output must be JSON with string values only
jq -n --arg tag "$LATEST_TAG" '{"latest_tag": $tag}'
```

```bash
chmod +x scripts/get_latest_tag.sh
```

**data.tf:**

```hcl
data "external" "latest_tag" {
  program = ["bash", "${path.module}/scripts/get_latest_tag.sh"]

  query = {
    repo = "/path/to/your/repo"
  }
}

output "latest_tag" {
  value = data.external.latest_tag.result.latest_tag
}
```

```bash
$ terraform apply

Outputs:

latest_tag = "v1.2.3"
```

### Another Example: Fetch Public IP

**scripts/my_ip.sh:**

```bash
#!/bin/bash
# No input needed, just fetch current public IP
MY_IP=$(curl -s https://checkip.amazonaws.com | tr -d '\n')
jq -n --arg ip "$MY_IP" '{"ip": $ip}'
```

```hcl
data "external" "my_ip" {
  program = ["bash", "${path.module}/scripts/my_ip.sh"]
}

resource "aws_security_group_rule" "ssh_from_me" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["${data.external.my_ip.result.ip}/32"]
  security_group_id = aws_security_group.main.id
}
```

> **Warning:** External data sources run every plan. If the script is slow or flaky, it slows down every Terraform operation. Use sparingly.

---

## 8. Combining Multiple Data Sources

A real-world pattern: look up VPC, find subnets, get latest AMI, and launch instances.

```hcl
# Find VPC
data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = ["production-vpc"]
  }
}

# Find subnets in that VPC
data "aws_subnets" "app_tier" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  filter {
    name   = "tag:Tier"
    values = ["app"]
  }
}

# Find latest AMI
data "aws_ami" "app" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["app-server-*"]
  }
}

# Find current AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Launch instances across subnets
resource "aws_instance" "app" {
  count         = length(data.aws_subnets.app_tier.ids)
  ami           = data.aws_ami.app.id
  instance_type = "t3.medium"
  subnet_id     = data.aws_subnets.app_tier.ids[count.index]

  tags = {
    Name = "app-server-${count.index}"
  }
}
```

---

## 9. Data Source Versioning and Dependencies

### Depends_on with Data Sources

Sometimes a data source needs to wait for a resource to be created first:

```hcl
resource "aws_vpc" "new" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "new-vpc"
  }
}

# This data source reads the VPC we just created
data "aws_vpc" "read_back" {
  id = aws_vpc.new.id

  depends_on = [aws_vpc.new]
}
```

### Lifecycle of Data Sources

```
Phase           What happens to data sources
-----           ----------------------------
terraform init  Nothing (data sources not read yet)
terraform plan  All data sources are READ from the provider
terraform apply Data sources are READ again, then resources act
terraform destroy Data sources are not re-read
```

---

## 10. Hands-On Lab: Complete Data Source Project

### Step 1: Project Setup

```bash
mkdir -p ~/data-source-lab && cd ~/data-source-lab
mkdir scripts
```

### Step 2: Create the Configuration

**providers.tf:**
```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
```

**data.tf:**
```hcl
# 1. Current account info
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# 2. Available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# 3. Default VPC
data "aws_vpc" "default" {
  default = true
}

# 4. Latest Amazon Linux AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# 5. External data source
data "external" "timestamp_info" {
  program = ["bash", "${path.module}/scripts/timestamp.sh"]
}
```

**scripts/timestamp.sh:**
```bash
#!/bin/bash
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DAY=$(date -u +"%A")
jq -n --arg ts "$NOW" --arg day "$DAY" '{"timestamp": $ts, "day_of_week": $day}'
```

**outputs.tf:**
```hcl
output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "region" {
  value = data.aws_region.current.name
}

output "availability_zones" {
  value = data.aws_availability_zones.available.names
}

output "default_vpc_id" {
  value = data.aws_vpc.default.id
}

output "latest_ami" {
  value = {
    id   = data.aws_ami.amazon_linux.id
    name = data.aws_ami.amazon_linux.name
  }
}

output "external_timestamp" {
  value = data.external.timestamp_info.result
}
```

### Step 3: Initialize and Apply

```bash
chmod +x scripts/timestamp.sh
terraform init
terraform apply -auto-approve
```

Expected output:
```
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

account_id         = "123456789012"
availability_zones = tolist([
  "us-east-1a",
  "us-east-1b",
  "us-east-1c",
  "us-east-1d",
  "us-east-1e",
  "us-east-1f",
])
default_vpc_id     = "vpc-0a1b2c3d"
external_timestamp = tomap({
  "day_of_week" = "Monday"
  "timestamp"   = "2024-03-15T10:30:00Z"
})
latest_ami = {
  "id"   = "ami-0abcdef1234567890"
  "name" = "al2023-ami-2023.3.20240312.0-kernel-6.1-x86_64"
}
region = "us-east-1"
```

> **Notice:** Zero resources were created. Data sources only read --- they do not create infrastructure.

---

## Summary

| Data Source | Use Case |
|-------------|----------|
| `aws_vpc` | Look up existing VPC by ID, tag, or default |
| `aws_subnets` | Find subnets with filters |
| `aws_ami` | Dynamic AMI lookup (no hard-coding) |
| `aws_availability_zones` | Spread resources across AZs |
| `aws_caller_identity` | Get current account ID and ARN |
| `aws_region` | Get current region name |
| `external` | Run custom scripts, return JSON |
| `template_file` | Render templates (deprecated, use `templatefile()`) |
| `local_file` | Read local files into Terraform |

> **Key takeaway:** Data sources are the bridge between "what already exists" and "what Terraform manages." Use them to avoid hard-coding IDs, to discover infrastructure dynamically, and to integrate with external systems.
