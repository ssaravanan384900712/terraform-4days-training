# 022 — Terraform AWS VPC, Subnets & Route Tables

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~20 minutes

## Topic

Every EC2 instance, RDS database, and container you launch in AWS lives inside a **VPC** (Virtual Private Cloud). A VPC is a logically isolated network you fully own and control.

AWS creates a **default VPC** in every region automatically. It is fine for quick demos, but it has open subnets, no network separation, and no tagging. For any real workload — including `robochef.co` — you create a **custom VPC** with the exact CIDR ranges, subnet layout, and routing you want.

This lab uses Terraform to build the foundational network for the `robochef-vpc` project:

- One **VPC** (`10.0.0.0/16`) with DNS support
- One **public subnet** (`10.0.1.0/24`) — instances here get a public IP and can reach the internet
- One **private subnet** (`10.0.2.0/24`) — instances here can only talk inside the VPC
- One **Internet Gateway (IGW)** — the door between the VPC and the public internet
- A **public route table** — sends `0.0.0.0/0` traffic to the IGW
- A **private route table** — routes only local VPC traffic (`10.0.0.0/16`)
- Two **route table associations** — one per subnet

**Default VPC vs Custom VPC:**

| | Default VPC | Custom VPC |
|---|---|---|
| CIDR | AWS assigns `172.31.0.0/16` | You choose (e.g. `10.0.0.0/16`) |
| Subnets | Auto-created, all public | You design — public and private |
| Internet Gateway | Pre-attached | You create and attach it |
| Tagging / naming | None | Fully controlled |
| Production use | Not recommended | Required |

---

## Architecture

```
VPC: 10.0.0.0/16 (robochef-vpc)
├── Public Subnet: 10.0.1.0/24  ─── Route Table ─── Internet Gateway (0.0.0.0/0)
└── Private Subnet: 10.0.2.0/24 ─── Route Table (local only)
```

Public subnet traffic path for `saravanans` EC2 instances at `robochef.co`:

```
EC2 (public subnet) → public route table → IGW → Internet
```

Private subnet traffic (e.g. RDS, Redis, internal services):

```
EC2 (private subnet) → private route table → VPC local only
```

---

## What Terraform Creates

```text
aws_vpc.main                           → robochef-vpc, CIDR 10.0.0.0/16
aws_internet_gateway.igw               → robochef-igw, attached to VPC
aws_subnet.public                      → robochef-public-subnet, 10.0.1.0/24
aws_subnet.private                     → robochef-private-subnet, 10.0.2.0/24
aws_route_table.public                 → robochef-public-rt, route 0.0.0.0/0 → IGW
aws_route_table_association.public     → links public subnet to public RT
aws_route_table.private                → robochef-private-rt, local only
aws_route_table_association.private    → links private subnet to private RT
```

**Plan: 8 to add, 0 to change, 0 to destroy.**

---

## 1. Create Project Folder

```bash
mkdir -p ~/terraform-vpc-022
cd ~/terraform-vpc-022
```

---

## 2. Check Your AWS Region

```bash
aws configure get region
aws sts get-caller-identity
```

The live test for this lab ran in `ap-south-1`. Update `terraform.tfvars` to match your configured region.

---

## 3. Create Terraform Files

Create the following files:

```text
providers.tf
variables.tf
main.tf
outputs.tf
terraform.tfvars
```

---

## 4. providers.tf

```bash
cat > providers.tf <<'EOF_TF'
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
provider "aws" { region = var.aws_region }
EOF_TF
```

---

## 5. variables.tf

```bash
cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}
variable "private_subnet_cidr" {
  type    = string
  default = "10.0.2.0/24"
}
variable "availability_zone" {
  type    = string
  default = "ap-south-1a"
}
EOF_TF
```

Five variables cover everything this lab needs. CIDR blocks and availability zone are overridden in `terraform.tfvars`.

---

## 6. main.tf

```bash
cat > main.tf <<'EOF_TF'
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "robochef-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "robochef-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true
  tags = { Name = "robochef-public-subnet" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone
  tags = { Name = "robochef-private-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "robochef-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "robochef-private-rt" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
EOF_TF
```

**Key connections in main.tf:**

```text
aws_vpc.main.id                    → aws_internet_gateway.igw.vpc_id
aws_vpc.main.id                    → aws_subnet.public.vpc_id
aws_vpc.main.id                    → aws_subnet.private.vpc_id
aws_vpc.main.id                    → aws_route_table.public.vpc_id
aws_vpc.main.id                    → aws_route_table.private.vpc_id
aws_internet_gateway.igw.id        → aws_route_table.public (route gateway_id)
aws_subnet.public.id               → aws_route_table_association.public.subnet_id
aws_subnet.private.id              → aws_route_table_association.private.subnet_id
aws_route_table.public.id          → aws_route_table_association.public.route_table_id
aws_route_table.private.id         → aws_route_table_association.private.route_table_id
```

---

## 7. outputs.tf

```bash
cat > outputs.tf <<'EOF_TF'
output "vpc_id"                 { value = aws_vpc.main.id }
output "vpc_cidr"               { value = aws_vpc.main.cidr_block }
output "public_subnet_id"       { value = aws_subnet.public.id }
output "private_subnet_id"      { value = aws_subnet.private.id }
output "internet_gateway_id"    { value = aws_internet_gateway.igw.id }
output "public_route_table_id"  { value = aws_route_table.public.id }
output "private_route_table_id" { value = aws_route_table.private.id }
EOF_TF
```

---

## 8. terraform.tfvars

```bash
cat > terraform.tfvars <<'EOF_TF'
aws_region          = "ap-south-1"
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.2.0/24"
availability_zone   = "ap-south-1a"
EOF_TF
```

Update `aws_region` and `availability_zone` to match your configured AWS region.

---

## 9. Initialize Terraform

```bash
terraform init
```

Expected output:

```text
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Installing hashicorp/aws v6.x.x...

Terraform has been successfully initialized!
```

---

## 10. Format and Validate

```bash
terraform fmt
terraform validate
```

Expected:

```text
Success! The configuration is valid.
```

---

## 11. Plan

```bash
terraform plan
```

Expected plan output:

```text
# aws_vpc.main will be created
  + resource "aws_vpc" "main" {
      + cidr_block           = "10.0.0.0/16"
      + enable_dns_hostnames = true
      + enable_dns_support   = true
      + tags                 = { "Name" = "robochef-vpc" }
    }

# aws_internet_gateway.igw will be created
# aws_subnet.public will be created
# aws_subnet.private will be created
# aws_route_table.public will be created
# aws_route_table_association.public will be created
# aws_route_table.private will be created
# aws_route_table_association.private will be created

Plan: 8 to add, 0 to change, 0 to destroy.
```

---

## 12. Apply

```bash
terraform apply
```

Type `yes` when prompted.

Expected output after apply:

```text
aws_vpc.main: Creating...
aws_vpc.main: Creation complete after 2s [id=vpc-0afdc71a1ce195d1d]
aws_internet_gateway.igw: Creating...
aws_subnet.public: Creating...
aws_subnet.private: Creating...
aws_internet_gateway.igw: Creation complete after 1s [id=igw-0a748572418be4cbf]
aws_subnet.public: Creation complete after 1s [id=subnet-02e762c1fdd6b7f2e]
aws_subnet.private: Creation complete after 1s [id=subnet-099287b24486c1c93]
aws_route_table.public: Creating...
aws_route_table.private: Creating...
aws_route_table.public: Creation complete after 1s [id=rtb-058ae1b683c36927c]
aws_route_table.private: Creation complete after 1s [id=rtb-084764985751825bf]
aws_route_table_association.public: Creating...
aws_route_table_association.private: Creating...
aws_route_table_association.public: Creation complete after 0s
aws_route_table_association.private: Creation complete after 0s

Apply complete! Resources: 8 added, 0 changed, 0 destroyed.

Outputs:

internet_gateway_id    = "igw-0a748572418be4cbf"
private_route_table_id = "rtb-084764985751825bf"
private_subnet_id      = "subnet-099287b24486c1c93"
public_route_table_id  = "rtb-058ae1b683c36927c"
public_subnet_id       = "subnet-02e762c1fdd6b7f2e"
vpc_cidr               = "10.0.0.0/16"
vpc_id                 = "vpc-0afdc71a1ce195d1d"
```

**Creation order Terraform used:**

1. `aws_vpc.main` is created first — everything depends on it
2. `aws_internet_gateway`, `aws_subnet.public`, `aws_subnet.private` are created in parallel (all need only the VPC ID)
3. `aws_route_table.public` and `aws_route_table.private` are created next
4. `aws_route_table_association.public` and `.private` are created last

---

## 13. Verify with AWS CLI

### Check the public route table

```bash
aws ec2 describe-route-tables \
  --route-table-ids rtb-058ae1b683c36927c \
  --region ap-south-1 \
  --query "RouteTables[0].Routes" \
  --output table
```

Expected output — two routes:

```text
----------------------------------------------------------------------
|                         DescribeRouteTables                        |
+------------------+----------------------------+--------------------+
| DestinationCidrBlock | GatewayId             | State              |
+------------------+----------------------------+--------------------+
| 10.0.0.0/16      | local                      | active             |
| 0.0.0.0/0        | igw-0a748572418be4cbf       | active             |
+------------------+----------------------------+--------------------+
```

The `0.0.0.0/0 → igw-0a748572418be4cbf` route confirms that instances in the public subnet can reach the internet.

### Check the private route table

```bash
aws ec2 describe-route-tables \
  --route-table-ids rtb-084764985751825bf \
  --region ap-south-1 \
  --query "RouteTables[0].Routes" \
  --output table
```

Expected output — one route only:

```text
----------------------------------------------
|         DescribeRouteTables                |
+----------------------+--------+------------+
| DestinationCidrBlock | GatewayId | State   |
+----------------------+--------+------------+
| 10.0.0.0/16          | local     | active  |
+----------------------+--------+------------+
```

Only `10.0.0.0/16 local` — the private subnet has no path to the internet.

### Confirm subnet settings

```bash
aws ec2 describe-subnets \
  --subnet-ids subnet-02e762c1fdd6b7f2e subnet-099287b24486c1c93 \
  --region ap-south-1 \
  --query "Subnets[*].{ID:SubnetId,CIDR:CidrBlock,PublicIP:MapPublicIpOnLaunch}" \
  --output table
```

Expected:

```text
-------------------------------------------------------------
|                     DescribeSubnets                       |
+----------------------------+--------------+--------------+
| ID                         | CIDR         | PublicIP     |
+----------------------------+--------------+--------------+
| subnet-02e762c1fdd6b7f2e   | 10.0.1.0/24  | True         |
| subnet-099287b24486c1c93   | 10.0.2.0/24  | False        |
+----------------------------+--------------+--------------+
```

---

## Concept: map_public_ip_on_launch

```hcl
map_public_ip_on_launch = true
```

This flag on `aws_subnet.public` tells AWS: every EC2 instance launched into this subnet automatically gets a **public IP address** — no extra configuration needed at the instance level.

Without this flag (default is `false`), instances in the subnet get only a private IP. They can talk to other resources in the VPC, but they cannot be reached from the internet and cannot reach the internet themselves (unless you add Elastic IPs or a NAT Gateway).

Set it on the **public subnet only**. The private subnet intentionally does not have it.

---

## Concept: enable_dns_hostnames

```hcl
enable_dns_hostnames = true
```

This flag on `aws_vpc.main` tells AWS to assign a **public DNS hostname** to EC2 instances that have a public IP. Without it, an EC2 instance in the public subnet gets a public IP but no hostname like:

```text
ec2-13-126-55-100.ap-south-1.compute.amazonaws.com
```

`enable_dns_support = true` (also set) tells the VPC to use the AWS-provided DNS resolver. Both flags together are required for EC2 hostname resolution to work correctly, and for some AWS services (like EFS, EKS, and PrivateLink endpoints) to resolve properly inside the VPC.

**Rule of thumb:** always set both flags to `true` in a custom VPC.

---

## 14. Destroy

After the demo, remove all AWS resources:

```bash
terraform destroy
```

Type `yes`.

Expected:

```text
aws_route_table_association.public: Destroying...
aws_route_table_association.private: Destroying...
aws_route_table_association.public: Destruction complete after 0s
aws_route_table_association.private: Destruction complete after 0s
aws_route_table.public: Destroying...
aws_route_table.private: Destroying...
aws_subnet.public: Destroying...
aws_subnet.private: Destroying...
aws_route_table.public: Destruction complete after 1s
aws_route_table.private: Destruction complete after 1s
aws_subnet.public: Destruction complete after 1s
aws_subnet.private: Destruction complete after 1s
aws_internet_gateway.igw: Destroying...
aws_internet_gateway.igw: Destruction complete after 1s
aws_vpc.main: Destroying...
aws_vpc.main: Destruction complete after 1s

Destroy complete! Resources: 8 destroyed.
```

Then clean up the provider cache:

```bash
rm -rf .terraform
```

---

## What Is Missing From This Lab

This lab builds the **network foundation** only. Two things are not yet covered:

**1. NAT Gateway — private subnet internet access**

Instances in the private subnet currently have no internet access at all. A NAT Gateway placed in the public subnet lets private instances make *outbound* internet requests (e.g. to install packages) without being reachable from the internet. NAT Gateway is covered in advanced labs.

```
Private EC2 → private RT → NAT Gateway (in public subnet) → IGW → Internet
```

**2. EC2 instances inside this VPC**

This lab creates the network but no instances. The next step is to launch EC2 instances using `subnet_id = aws_subnet.public.id` or `subnet_id = aws_subnet.private.id` to place them in the correct subnet.

---

## Full Copy-Paste Setup Script

```bash
mkdir -p ~/terraform-vpc-022
cd ~/terraform-vpc-022

cat > providers.tf <<'EOF_TF'
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
provider "aws" { region = var.aws_region }
EOF_TF

cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}
variable "private_subnet_cidr" {
  type    = string
  default = "10.0.2.0/24"
}
variable "availability_zone" {
  type    = string
  default = "ap-south-1a"
}
EOF_TF

cat > main.tf <<'EOF_TF'
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "robochef-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "robochef-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true
  tags = { Name = "robochef-public-subnet" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone
  tags = { Name = "robochef-private-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "robochef-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "robochef-private-rt" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
EOF_TF

cat > outputs.tf <<'EOF_TF'
output "vpc_id"                 { value = aws_vpc.main.id }
output "vpc_cidr"               { value = aws_vpc.main.cidr_block }
output "public_subnet_id"       { value = aws_subnet.public.id }
output "private_subnet_id"      { value = aws_subnet.private.id }
output "internet_gateway_id"    { value = aws_internet_gateway.igw.id }
output "public_route_table_id"  { value = aws_route_table.public.id }
output "private_route_table_id" { value = aws_route_table.private.id }
EOF_TF

MY_REGION=$(aws configure get region 2>/dev/null || echo "ap-south-1")

cat > terraform.tfvars <<EOF_TF
aws_region          = "${MY_REGION}"
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.2.0/24"
availability_zone   = "${MY_REGION}a"
EOF_TF

terraform init
terraform fmt
terraform validate
terraform plan
```

Then apply:

```bash
terraform apply
```

---

## Concept Summary

| Resource / Concept | What It Does |
|---|---|
| `aws_vpc` | Creates a logically isolated private network in AWS with a CIDR block you control |
| `aws_subnet` | Divides the VPC into smaller address ranges; each subnet lives in one availability zone |
| `aws_internet_gateway` | Attaches an internet-facing gateway to the VPC; required for any public internet traffic |
| `aws_route_table` | Defines routing rules — which traffic goes where (local VPC or out to IGW) |
| `aws_route_table_association` | Links a route table to a specific subnet; one association per subnet |
| `cidr_block` | The IP address range in CIDR notation, e.g. `10.0.0.0/16` (65,536 addresses) |
| `map_public_ip_on_launch` | When `true`, every EC2 instance launched into the subnet auto-receives a public IP |
| `enable_dns_hostnames` | When `true`, AWS assigns a public DNS hostname to instances with public IPs; required for EFS, EKS, and PrivateLink to resolve correctly inside the VPC |
