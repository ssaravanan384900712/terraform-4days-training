# Hands-On 4.6 — Capstone Project: Production EKS Deployment

**File:** `~/capstone/`

---

## Concept

This capstone brings together everything from the 4-day training into a single end-to-end project. You will build a production-grade EKS cluster on AWS with proper networking, security, CI/CD, testing, and operational workflows. Each phase adds a layer, and by the end you have a fully operational infrastructure codebase following real-world best practices.

### Architecture Overview

```
  +------------------------------------------------------------------------+
  |  AWS Account                                                           |
  |                                                                        |
  |  +-------------------+  +-------------------+  +-------------------+   |
  |  |  VPC (10.0.0.0/16)|  |  KMS Key          |  |  S3 State Bucket |   |
  |  |  +------+ +------+|  |  (state + secrets) |  |  (versioned,     |   |
  |  |  |pub-1 | |pub-2 ||  +-------------------+  |   encrypted)     |   |
  |  |  |subnet| |subnet||                         +-------------------+   |
  |  |  +--+---+ +--+---+|                                                 |
  |  |     |         |    |  +-------------------------------------------+ |
  |  |  +--+---+ +--+---+|  |  EKS Cluster                              | |
  |  |  |priv-1| |priv-2||  |  +------------+  +---------------------+  | |
  |  |  |subnet| |subnet||  |  | Control    |  | Node Group          |  | |
  |  |  +------+ +------+|  |  | Plane      |  | (t3.medium x 2-4)  |  | |
  |  |                    |  |  +------------+  +---------------------+  | |
  |  |  +------+ +------+|  +-------------------------------------------+ |
  |  |  | NAT  | | IGW  ||                                                 |
  |  |  | GW   | |      ||  +-------------------------------------------+ |
  |  |  +------+ +------+|  |  IAM Roles                                | |
  |  +-------------------+  |  - EKS Cluster Role                       | |
  |                          |  - Node Group Role                        | |
  |                          |  - Terraform CI Role                      | |
  |                          +-------------------------------------------+ |
  +------------------------------------------------------------------------+
```

### Project Phases

```
  Phase 1          Phase 2         Phase 3         Phase 4
  Bootstrap  --->  Networking --->  Compute   --->  Security
  (state,          (VPC,            (EKS,           (IAM,
   structure)       subnets)         nodes)          KMS)
       |                                               |
       v                                               v
  Phase 7          Phase 6         Phase 5
  Operations <---  Testing   <---  CI/CD
  (import,          (terraform      (GitHub
   state ops)       test, tfsec)    Actions)
```

---

## Phase 1 — Bootstrap (Remote State and Project Structure)

### Step 1: Create the project structure

```bash
mkdir -p ~/capstone/{modules/{vpc,eks,security,tags},environments/{dev,prod},tests,scripts,.github/workflows}
cd ~/capstone
git init
```

### Full Directory Tree

```
capstone/
  .github/
    workflows/
      terraform.yml           # CI/CD pipeline
  modules/
    vpc/
      main.tf
      variables.tf
      outputs.tf
    eks/
      main.tf
      variables.tf
      outputs.tf
    security/
      main.tf
      variables.tf
      outputs.tf
    tags/
      main.tf
      variables.tf
      outputs.tf
  environments/
    dev/
      main.tf
      variables.tf
      terraform.tfvars
      backend.tf
      outputs.tf
    prod/
      main.tf
      variables.tf
      terraform.tfvars
      backend.tf
      outputs.tf
  tests/
    tags.tftest.hcl
    vpc.tftest.hcl
  scripts/
    bootstrap-state.sh
  .pre-commit-config.yaml
  .terraform-version
  CLAUDE.md
```

### Step 2: Pin Terraform version

```bash
echo "1.8.0" > ~/capstone/.terraform-version
```

### Step 3: Bootstrap remote state

```bash
cat > ~/capstone/scripts/bootstrap-state.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="capstone-tfstate-${ACCOUNT_ID}"
TABLE_NAME="capstone-terraform-locks"
REGION="us-east-1"

echo "==> Creating S3 bucket: ${BUCKET_NAME}"
aws s3api create-bucket \
  --bucket "${BUCKET_NAME}" \
  --region "${REGION}"

echo "==> Enabling versioning"
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled

echo "==> Enabling encryption"
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms"
      },
      "BucketKeyEnabled": true
    }]
  }'

echo "==> Blocking public access"
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "==> Creating DynamoDB lock table: ${TABLE_NAME}"
aws dynamodb create-table \
  --table-name "${TABLE_NAME}" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "${REGION}" \
  --tags Key=ManagedBy,Value=bootstrap Key=Project,Value=capstone

echo "==> Bootstrap complete!"
echo "    Bucket: ${BUCKET_NAME}"
echo "    Table:  ${TABLE_NAME}"
SCRIPT

chmod +x ~/capstone/scripts/bootstrap-state.sh
```

```bash
# Run the bootstrap
~/capstone/scripts/bootstrap-state.sh
```

---

## Phase 2 — Networking (VPC Module)

### Step 4: Tags module (shared across all resources)

```hcl
# modules/tags/variables.tf

variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "owner" {
  type    = string
  default = "platform-team"
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}
```

```hcl
# modules/tags/main.tf

locals {
  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "terraform"
    },
    var.extra_tags
  )
}
```

```hcl
# modules/tags/outputs.tf

output "tags" {
  value = local.tags
}
```

### Step 5: VPC module

```hcl
# modules/vpc/variables.tf

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs"
  type        = list(string)
}

variable "availability_zones" {
  description = "AZs for subnets"
  type        = list(string)
}

variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
```

```hcl
# modules/vpc/main.tf

# --- VPC ---
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-vpc"
  })
}

# --- Public Subnets ---
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                           = "${var.project}-${var.environment}-public-${count.index}"
    "kubernetes.io/role/elb"                        = "1"
    "kubernetes.io/cluster/${var.project}-${var.environment}" = "shared"
  })
}

# --- Private Subnets ---
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name                                           = "${var.project}-${var.environment}-private-${count.index}"
    "kubernetes.io/role/internal-elb"               = "1"
    "kubernetes.io/cluster/${var.project}-${var.environment}" = "shared"
  })
}

# --- Internet Gateway ---
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-igw"
  })
}

# --- Elastic IP for NAT ---
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-nat-eip"
  })
}

# --- NAT Gateway ---
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-nat"
  })

  depends_on = [aws_internet_gateway.this]
}

# --- Public Route Table ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- Private Route Table ---
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

```hcl
# modules/vpc/outputs.tf

output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "nat_gateway_ip" {
  value = aws_eip.nat.public_ip
}
```

---

## Phase 3 — Compute (EKS Cluster)

### Step 6: EKS module

```hcl
# modules/eks/variables.tf

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets for the EKS cluster (private recommended)"
  type        = list(string)
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

```hcl
# modules/eks/main.tf

# --- EKS Cluster IAM Role ---
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

# --- EKS Cluster ---
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.cluster.id]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_controller,
  ]
}

# --- Cluster Security Group ---
resource "aws_security_group" "cluster" {
  name_prefix = "${var.cluster_name}-cluster-"
  vpc_id      = var.vpc_id
  description = "EKS cluster security group"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "Allow HTTPS from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-cluster-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# --- Node Group IAM Role ---
resource "aws_iam_role" "node_group" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group.name
}

# --- EKS Node Group ---
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.subnet_ids

  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.node_policy,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}
```

```hcl
# modules/eks/outputs.tf

output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  value = aws_security_group.cluster.id
}

output "node_group_role_arn" {
  value = aws_iam_role.node_group.arn
}
```

---

## Phase 4 — Security (IAM, KMS, Secrets)

### Step 7: Security module

```hcl
# modules/security/variables.tf

variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

```hcl
# modules/security/main.tf

# --- KMS Key for secrets ---
resource "aws_kms_key" "secrets" {
  description             = "${var.project}-${var.environment} secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-secrets-key"
  })
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.project}-${var.environment}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# --- SSM Parameters for app config ---
resource "aws_ssm_parameter" "app_config" {
  name  = "/${var.project}/${var.environment}/app/config"
  type  = "SecureString"
  value = jsonencode({
    log_level   = var.environment == "prod" ? "warn" : "debug"
    enable_debug = var.environment != "prod"
  })
  key_id = aws_kms_key.secrets.arn

  tags = var.tags
}

# --- Terraform CI/CD IAM Role ---
resource "aws_iam_role" "terraform_ci" {
  name = "${var.project}-${var.environment}-terraform-ci"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:myorg/capstone:*"
        }
      }
    }]
  })

  tags = var.tags
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "terraform_ci" {
  name = "terraform-ci-policy"
  role = aws_iam_role.terraform_ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSManagement"
        Effect = "Allow"
        Action = [
          "eks:*",
          "ec2:Describe*",
          "ec2:CreateVpc",
          "ec2:DeleteVpc",
          "ec2:*Subnet*",
          "ec2:*SecurityGroup*",
          "ec2:*RouteTable*",
          "ec2:*InternetGateway*",
          "ec2:*NatGateway*",
          "ec2:*Address*",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "iam:GetRole",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:PassRole",
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider"
        ]
        Resource = "*"
      },
      {
        Sid    = "StateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::capstone-tfstate-*",
          "arn:aws:s3:::capstone-tfstate-*/*"
        ]
      },
      {
        Sid    = "StateLocking"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:*:*:table/capstone-terraform-locks"
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
          "kms:CreateKey",
          "kms:CreateAlias",
          "kms:DeleteAlias"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMAccess"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter",
          "ssm:DeleteParameter"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/${var.project}/*"
      }
    ]
  })
}
```

```hcl
# modules/security/outputs.tf

output "kms_key_arn" {
  value = aws_kms_key.secrets.arn
}

output "kms_key_alias" {
  value = aws_kms_alias.secrets.name
}

output "terraform_ci_role_arn" {
  value = aws_iam_role.terraform_ci.arn
}
```

---

## Phase 4b — Environment Root Module (Wiring Everything Together)

### Step 8: Dev environment

```hcl
# environments/dev/backend.tf

terraform {
  backend "s3" {
    bucket         = "capstone-tfstate-ACCOUNT_ID"    # Replace with actual
    key            = "dev/capstone.tfstate"
    region         = "us-east-1"
    dynamodb_table = "capstone-terraform-locks"
    encrypt        = true
  }
}
```

```hcl
# environments/dev/variables.tf

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "capstone"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "eks_node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "eks_node_desired_size" {
  type    = number
  default = 2
}
```

```hcl
# environments/dev/terraform.tfvars

aws_region              = "us-east-1"
project                 = "capstone"
environment             = "dev"
vpc_cidr                = "10.0.0.0/16"
eks_node_instance_types = ["t3.medium"]
eks_node_desired_size   = 2
```

```hcl
# environments/dev/main.tf

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# --- Locals for dynamic configuration ---
locals {
  azs = ["${var.aws_region}a", "${var.aws_region}b"]

  public_subnet_cidrs  = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i + 10)]

  cluster_name = "${var.project}-${var.environment}"

  # Environment-specific overrides via maps
  config = {
    dev = {
      node_desired = 2
      node_max     = 3
      k8s_version  = "1.29"
    }
    prod = {
      node_desired = 3
      node_max     = 6
      k8s_version  = "1.29"
    }
  }

  env_config = local.config[var.environment]
}

# --- Tags ---
module "tags" {
  source = "../../modules/tags"

  project     = var.project
  environment = var.environment
  owner       = "platform-team"
}

# --- VPC ---
module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = local.public_subnet_cidrs
  private_subnet_cidrs = local.private_subnet_cidrs
  availability_zones   = local.azs
  project              = var.project
  environment          = var.environment
  tags                 = module.tags.tags
}

# --- EKS ---
module "eks" {
  source = "../../modules/eks"

  cluster_name        = local.cluster_name
  cluster_version     = local.env_config.k8s_version
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  node_instance_types = var.eks_node_instance_types
  node_desired_size   = local.env_config.node_desired
  node_min_size       = 1
  node_max_size       = local.env_config.node_max
  tags                = module.tags.tags
}

# --- Security ---
module "security" {
  source = "../../modules/security"

  project     = var.project
  environment = var.environment
  tags        = module.tags.tags
}
```

```hcl
# environments/dev/outputs.tf

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "kms_key_arn" {
  value = module.security.kms_key_arn
}

output "terraform_ci_role_arn" {
  value = module.security.terraform_ci_role_arn
}
```

---

## Phase 5 — CI/CD (GitHub Actions Pipeline)

### Step 9: GitHub Actions workflow

```yaml
# .github/workflows/terraform.yml

name: Terraform CI/CD

on:
  pull_request:
    branches: [main]
    paths:
      - 'modules/**'
      - 'environments/**'
  push:
    branches: [main]
    paths:
      - 'modules/**'
      - 'environments/**'

permissions:
  id-token: write      # For OIDC
  contents: read
  pull-requests: write  # For PR comments

env:
  TF_IN_AUTOMATION: true
  AWS_REGION: us-east-1

jobs:
  # --- Static Analysis ---
  lint:
    name: Lint & Security Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.8.0"

      - name: Terraform Format Check
        run: terraform fmt -check -recursive

      - name: Install tfsec
        run: |
          curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash

      - name: Run tfsec
        run: tfsec . --minimum-severity HIGH

      - name: Install checkov
        run: pip install checkov

      - name: Run checkov
        run: checkov -d . --framework terraform --quiet

  # --- Unit Tests ---
  test:
    name: Terraform Tests
    runs-on: ubuntu-latest
    needs: lint
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.8.0"

      - name: Terraform Test
        run: |
          cd environments/dev
          terraform init -backend=false
          terraform test

  # --- Plan (on PR) ---
  plan:
    name: Terraform Plan
    runs-on: ubuntu-latest
    needs: [lint, test]
    if: github.event_name == 'pull_request'
    strategy:
      matrix:
        environment: [dev]
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.TF_CI_ROLE_ARN }}
          aws-region: us-east-1

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.8.0"

      - name: Terraform Init
        working-directory: environments/${{ matrix.environment }}
        run: terraform init

      - name: Terraform Plan
        id: plan
        working-directory: environments/${{ matrix.environment }}
        run: terraform plan -no-color -out=tfplan
        continue-on-error: true

      - name: Comment PR with Plan
        uses: actions/github-script@v7
        with:
          script: |
            const output = `#### Terraform Plan - ${{ matrix.environment }}
            \`\`\`
            ${{ steps.plan.outputs.stdout }}
            \`\`\`
            *Triggered by @${{ github.actor }}*`;
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output
            });

  # --- Apply (on merge to main) ---
  apply:
    name: Terraform Apply
    runs-on: ubuntu-latest
    needs: [lint, test]
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment: dev       # Requires GitHub environment approval
    strategy:
      matrix:
        environment: [dev]
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.TF_CI_ROLE_ARN }}
          aws-region: us-east-1

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.8.0"

      - name: Terraform Init
        working-directory: environments/${{ matrix.environment }}
        run: terraform init

      - name: Terraform Apply
        working-directory: environments/${{ matrix.environment }}
        run: terraform apply -auto-approve
```

### GitOps Workflow

```
  Developer        GitHub              CI/CD             AWS
  +------+        +------+           +-------+         +-----+
  | edit |        | PR   |           | lint  |         |     |
  | push |------->| open |---------->| test  |         |     |
  | PR   |        |      |<----+     | plan  |         |     |
  +------+        |      |    |      +---+---+         |     |
                  |      |    +----------+ (comment)   |     |
  +------+        |      |                              |     |
  | review|       | merge|---------->+-------+         |     |
  | approve|----->| main |           | apply |-------->| EKS |
  +------+        +------+           +-------+         +-----+
```

---

## Phase 6 — Testing and Compliance

### Step 10: terraform test files

```hcl
# tests/tags.tftest.hcl

run "standard_tags" {
  command = plan

  module {
    source = "./modules/tags"
  }

  variables {
    project     = "capstone"
    environment = "dev"
  }

  assert {
    condition     = output.tags["Project"] == "capstone"
    error_message = "Project tag mismatch"
  }

  assert {
    condition     = output.tags["ManagedBy"] == "terraform"
    error_message = "ManagedBy tag should be 'terraform'"
  }
}

run "prod_tags" {
  command = plan

  module {
    source = "./modules/tags"
  }

  variables {
    project     = "capstone"
    environment = "prod"
    owner       = "sre-team"
    extra_tags  = {
      Compliance = "soc2"
    }
  }

  assert {
    condition     = output.tags["Owner"] == "sre-team"
    error_message = "Owner should be overridden to sre-team"
  }

  assert {
    condition     = output.tags["Compliance"] == "soc2"
    error_message = "Extra tags should be merged"
  }
}
```

```hcl
# tests/vpc.tftest.hcl

run "vpc_creates_correct_subnets" {
  command = plan

  module {
    source = "./modules/vpc"
  }

  variables {
    vpc_cidr             = "10.99.0.0/16"
    public_subnet_cidrs  = ["10.99.0.0/24", "10.99.1.0/24"]
    private_subnet_cidrs = ["10.99.10.0/24", "10.99.11.0/24"]
    availability_zones   = ["us-east-1a", "us-east-1b"]
    project              = "test"
    environment          = "ci"
  }

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "Should create 2 public subnets"
  }

  assert {
    condition     = length(aws_subnet.private) == 2
    error_message = "Should create 2 private subnets"
  }

  assert {
    condition     = aws_vpc.this.cidr_block == "10.99.0.0/16"
    error_message = "VPC CIDR should match input"
  }
}
```

### Step 11: Policy as Code (OPA Example)

```rego
# policy/terraform.rego -- Open Policy Agent policy

package terraform

# Deny resources without required tags
deny[msg] {
  resource := input.planned_values.root_module.resources[_]
  not resource.values.tags["Environment"]
  msg := sprintf("Resource %s missing 'Environment' tag", [resource.address])
}

deny[msg] {
  resource := input.planned_values.root_module.resources[_]
  not resource.values.tags["ManagedBy"]
  msg := sprintf("Resource %s missing 'ManagedBy' tag", [resource.address])
}

# Deny overly permissive security groups
deny[msg] {
  resource := input.planned_values.root_module.resources[_]
  resource.type == "aws_security_group"
  ingress := resource.values.ingress[_]
  ingress.cidr_blocks[_] == "0.0.0.0/0"
  ingress.from_port == 0
  ingress.to_port == 0
  msg := sprintf("Security group %s allows unrestricted access on all ports", [resource.address])
}

# Enforce instance type restrictions
deny[msg] {
  resource := input.planned_values.root_module.resources[_]
  resource.type == "aws_instance"
  not startswith(resource.values.instance_type, "t3.")
  not startswith(resource.values.instance_type, "t4g.")
  msg := sprintf("Instance %s uses non-approved type: %s", [resource.address, resource.values.instance_type])
}
```

```bash
# Run OPA against Terraform plan
cd ~/capstone/environments/dev

terraform plan -out=tfplan
terraform show -json tfplan > plan.json

# Evaluate policy
opa eval --data policy/terraform.rego --input plan.json "data.terraform.deny"
```

### Step 12: pre-commit configuration

```yaml
# .pre-commit-config.yaml

repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.96.1
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tfsec
        args: ['--args=--minimum-severity HIGH']
      - id: terraform_docs

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-merge-conflict
      - id: detect-private-key
```

```bash
pip install pre-commit
pre-commit install
pre-commit run --all-files
```

---

## Phase 7 — Operations (Import, State Ops, Destroy)

### Step 13: Importing unmanaged resources

```bash
cd ~/capstone/environments/dev

# Scenario: An S3 bucket was created manually and needs to be managed
aws s3 mb s3://capstone-unmanaged-demo-$(date +%s)
```

Add config for the existing resource:

```hcl
# Add to environments/dev/main.tf

resource "aws_s3_bucket" "imported_bucket" {
  bucket = "capstone-unmanaged-demo-TIMESTAMP"     # Replace with actual

  tags = merge(module.tags.tags, {
    Name = "imported-bucket"
  })
}
```

```bash
# Method 1: CLI import
terraform import aws_s3_bucket.imported_bucket capstone-unmanaged-demo-TIMESTAMP

# Method 2: Import block (Terraform 1.5+)
# Add to main.tf:
# import {
#   to = aws_s3_bucket.imported_bucket
#   id = "capstone-unmanaged-demo-TIMESTAMP"
# }

terraform plan
# Verify: should show minimal or no changes
```

### Step 14: State lifecycle operations

```bash
# --- List all resources ---
terraform state list
# module.vpc.aws_vpc.this
# module.vpc.aws_subnet.public[0]
# module.vpc.aws_subnet.public[1]
# module.eks.aws_eks_cluster.this
# ...

# --- Show resource details ---
terraform state show module.vpc.aws_vpc.this

# --- Move a resource (rename) ---
# Scenario: Rename a module
terraform state mv module.security module.iam_security

# --- Remove from state (without destroying) ---
# Scenario: Hand off a resource to another team's state
terraform state rm aws_s3_bucket.imported_bucket
# The bucket still exists in AWS but is no longer managed here

# --- Pull state for backup/inspection ---
terraform state pull > state-backup-$(date +%Y%m%d).json

# --- Push state (DANGEROUS -- use only for recovery) ---
# terraform state push state-backup-20260518.json

# --- Force unlock (when lock is stuck) ---
# terraform force-unlock LOCK_ID
```

### Step 15: AWS Resource Lifecycle demonstration

```bash
# CREATE
terraform apply -auto-approve
# All resources created

# UPDATE (change a variable)
terraform apply -var='eks_node_desired_size=3' -auto-approve
# Node group scales from 2 to 3

# READ (inspect current state)
terraform show
terraform output

# IMPORT (bring in external resource)
terraform import aws_s3_bucket.imported_bucket my-bucket-name

# DESTROY (targeted)
terraform destroy -target=aws_s3_bucket.imported_bucket -auto-approve

# DESTROY (full teardown)
terraform destroy -auto-approve
```

### Step 16: Ansible integration for EC2 configuration

```hcl
# Add to environments/dev/main.tf -- optional bastion host

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = module.vpc.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.bastion.id]
  key_name               = aws_key_pair.deploy.key_name

  tags = merge(module.tags.tags, {
    Name = "${var.project}-${var.environment}-bastion"
    Role = "bastion"
  })
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "tls_private_key" "deploy" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "deploy" {
  key_name   = "${var.project}-${var.environment}-deploy"
  public_key = tls_private_key.deploy.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.deploy.private_key_pem
  filename        = "${path.module}/deploy-key.pem"
  file_permission = "0600"
}

resource "aws_security_group" "bastion" {
  name_prefix = "${var.project}-bastion-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]    # Restrict to your IP in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Dynamic Ansible inventory ---
resource "local_file" "ansible_inventory" {
  content = <<-INV
    [bastion]
    ${aws_instance.bastion.public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=deploy-key.pem

    [bastion:vars]
    ansible_ssh_common_args='-o StrictHostKeyChecking=no'
    eks_cluster_name=${module.eks.cluster_name}
    aws_region=${var.aws_region}
  INV
  filename = "${path.module}/inventory.ini"
}
```

```yaml
# environments/dev/playbook.yml

---
- hosts: bastion
  become: true
  tasks:
    - name: Install kubectl
      get_url:
        url: https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl
        dest: /usr/local/bin/kubectl
        mode: '0755'

    - name: Install AWS CLI v2
      shell: |
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip -q awscliv2.zip
        ./aws/install --update
      args:
        creates: /usr/local/bin/aws

    - name: Configure kubeconfig
      shell: |
        aws eks update-kubeconfig \
          --name {{ eks_cluster_name }} \
          --region {{ aws_region }}
      become: false
```

```bash
# After terraform apply:
ansible-playbook -i inventory.ini playbook.yml
```

---

## Deployment Commands Reference

```bash
cd ~/capstone/environments/dev

# --- Full deployment sequence ---
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan

# --- Connect to EKS ---
aws eks update-kubeconfig \
  --name $(terraform output -raw eks_cluster_name) \
  --region us-east-1

kubectl get nodes
# NAME                            STATUS   ROLES    AGE   VERSION
# ip-10-0-10-42.ec2.internal     Ready    <none>   5m    v1.29.x
# ip-10-0-11-87.ec2.internal     Ready    <none>   5m    v1.29.x

# --- Run tests ---
terraform test
tfsec .
checkov -d .

# --- Full teardown (in reverse order) ---
terraform destroy -auto-approve
```

---

## 1-Click App Deployment (tfvars-driven)

Create environment-specific tfvars for quick replication:

```hcl
# environments/prod/terraform.tfvars

aws_region              = "us-east-1"
project                 = "capstone"
environment             = "prod"
vpc_cidr                = "10.1.0.0/16"
eks_node_instance_types = ["t3.large"]
eks_node_desired_size   = 3
```

```bash
# Deploy prod with a single command
cd ~/capstone/environments/prod
terraform init
terraform apply -auto-approve

# Deploy dev
cd ~/capstone/environments/dev
terraform apply -auto-approve

# Both environments are fully isolated (separate VPCs, state files, IAM)
```

---

## Summary: What You Built

| Phase | What | Key Concepts |
|-------|------|-------------|
| 1. Bootstrap | S3 + DynamoDB state backend | Remote state, locking, encryption |
| 2. Networking | VPC with public/private subnets, NAT | Module composition, EKS-ready tagging |
| 3. Compute | EKS cluster + managed node group | IAM roles, cluster config, scaling |
| 4. Security | KMS, SSM, CI IAM role | Least privilege, secrets management |
| 5. CI/CD | GitHub Actions pipeline | GitOps, plan-on-PR, apply-on-merge |
| 6. Testing | terraform test, tfsec, checkov, OPA | Testing pyramid, policy as code |
| 7. Operations | Import, state ops, Ansible | Day-2 operations, lifecycle management |

### Skills Demonstrated

- Remote state with encryption and locking
- Modular design (VPC, EKS, Security, Tags)
- Environment isolation with tfvars
- Dynamic configuration with locals and maps
- IAM least privilege (OIDC for CI/CD)
- Secrets management (KMS + SSM)
- CI/CD pipeline (lint, test, plan, apply)
- Policy as code (OPA)
- Resource import strategies
- State management operations
- Ansible integration for configuration
- GitOps operating model
