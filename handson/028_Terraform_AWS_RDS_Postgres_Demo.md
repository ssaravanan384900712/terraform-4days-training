# 028 — Terraform AWS RDS Postgres Demo

**By: Saravanan Sundaramoorthy**
**Environment:** AWS ap-south-1 (Mumbai)
**Time to complete:** ~20 minutes

---

## Topic

| Concept | What it means |
|---------|--------------|
| **aws_db_instance** | Terraform resource that provisions an RDS database instance |
| **aws_db_subnet_group** | Groups subnets where RDS can place the instance |
| **aws_security_group** | Controls which IPs/ports can reach the database |
| **engine_version** | Must be an exact version AWS supports — not every patch is available in every region |
| **skip_final_snapshot** | Set `true` in labs so destroy works without naming a final backup snapshot |
| **publicly_accessible** | Allows connection from outside the VPC — demo only, never in production |
| **sensitive password** | Declared as `sensitive = true` so Terraform hides it from plan/apply output |

RDS is the AWS managed relational database service. This lab provisions a **PostgreSQL 16.14** instance on a `db.t3.micro` (free-tier eligible), verifies the connection with `psql`, and then destroys everything cleanly.

---

## Architecture

```
                          ap-south-1
  ┌───────────────────────────────────────────────────────┐
  │                                                       │
  │   Default VPC                                         │
  │  ┌─────────────────────────────────────────────────┐  │
  │  │                                                 │  │
  │  │  aws_db_subnet_group  (all default subnets)     │  │
  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐      │  │
  │  │  │ subnet-a │  │ subnet-b │  │ subnet-c │      │  │
  │  │  └────┬─────┘  └────┬─────┘  └────┬─────┘      │  │
  │  │       └─────────────┴─────────────┘             │  │
  │  │                      │                          │  │
  │  │         ┌────────────▼─────────────┐            │  │
  │  │         │  aws_db_instance         │            │  │
  │  │         │  postgres 16.14          │            │  │
  │  │         │  db.t3.micro / 20GB gp2  │            │  │
  │  │         │  identifier: 028-postgres│            │  │
  │  │         └────────────┬─────────────┘            │  │
  │  │                      │ port 5432                │  │
  │  │         ┌────────────▼─────────────┐            │  │
  │  │         │  aws_security_group      │            │  │
  │  │         │  ingress 0.0.0.0/0:5432  │            │  │
  │  │         └──────────────────────────┘            │  │
  │  └─────────────────────────────────────────────────┘  │
  └───────────────────────────────────────────────────────┘
            │
            │  publicly_accessible = true
            │
       Your laptop
       psql -h <endpoint> -U robochef -d robochefdb
```

---

## What Terraform Creates

| # | Resource | Name | Purpose |
|---|----------|------|---------|
| 1 | `random_string.suffix` | 6-char suffix | Makes names unique across re-runs |
| 2 | `aws_security_group.rds` | terraform-028-rds-sg | Opens port 5432 from anywhere (demo only) |
| 3 | `aws_db_subnet_group.demo` | terraform-028-rds-subnet-group | Tells RDS which subnets to use |
| 4 | `aws_db_instance.postgres` | terraform-028-postgres | The actual Postgres 16.14 database |

---

## Step 1 — Create the project directory

```bash
mkdir ~/terraform-aws-028-rds && cd ~/terraform-aws-028-rds
```

---

## Step 2 — Write the Terraform files

### providers.tf

```bash
cat > providers.tf <<'EOF_TF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
EOF_TF
```

### variables.tf

```bash
cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "db_password" {
  description = "Master password for the RDS Postgres instance"
  type        = string
  sensitive   = true
  default     = "Robochef2024!"
  # WARNING: Never use a hardcoded default password in production.
  # Use TF_VAR_db_password env var or AWS Secrets Manager instead.
}
EOF_TF
```

### main.tf

```bash
cat > main.tf <<'EOF_TF'
# ── Data sources: default VPC + its subnets ──────────────────────────────────
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ── Random suffix so the identifier is unique across re-runs ─────────────────
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# ── Security group: allow Postgres from anywhere (demo only) ─────────────────
resource "aws_security_group" "rds" {
  name        = "terraform-028-rds-sg"
  description = "Allow Postgres from anywhere (demo only)"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "terraform-028-rds-sg"
    Owner = "saravanans"
  }
}

# ── DB subnet group: place RDS in all default subnets ────────────────────────
resource "aws_db_subnet_group" "demo" {
  name       = "terraform-028-rds-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
}

# ── RDS Postgres instance ─────────────────────────────────────────────────────
resource "aws_db_instance" "postgres" {
  identifier        = "terraform-028-postgres"
  engine            = "postgres"
  engine_version    = "16.14"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "robochefdb"
  username = "robochef"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.demo.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  skip_final_snapshot = true   # required for clean destroy in labs
  publicly_accessible = true   # demo only — never in production
  multi_az            = false

  tags = {
    Name    = "terraform-028-postgres"
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}
EOF_TF
```

### outputs.tf

```bash
cat > outputs.tf <<'EOF_TF'
output "db_endpoint" {
  description = "Full RDS endpoint including port"
  value       = aws_db_instance.postgres.endpoint
}

output "db_host" {
  description = "RDS hostname (without port)"
  value       = aws_db_instance.postgres.address
}

output "db_port" {
  description = "RDS port"
  value       = aws_db_instance.postgres.port
}

output "db_name" {
  description = "Database name created inside the instance"
  value       = aws_db_instance.postgres.db_name
}

output "psql_connect" {
  description = "Ready-to-run psql command"
  value       = "psql -h ${aws_db_instance.postgres.address} -U robochef -d robochefdb -p 5432"
}
EOF_TF
```

---

## Step 3 — Check available engine versions (if needed)

> **Important fix discovered during live testing:**
> `engine_version = "16.3"` was NOT available in ap-south-1. Always verify
> which exact patch versions AWS offers before running `apply`.

```bash
aws rds describe-db-engine-versions \
  --engine postgres \
  --region ap-south-1 \
  --query 'DBEngineVersions[*].EngineVersion' \
  --output text
```

The version used in this lab — **16.14** — was confirmed available.

---

## Step 4 — Init, Format, Validate, Plan

```bash
terraform init
```

Expected output:
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Finding hashicorp/random versions matching "~> 3.0"...
- Installed hashicorp/aws v6.x.x
- Installed hashicorp/random v3.x.x
Terraform has been successfully initialized!
```

```bash
terraform fmt
terraform validate
```

Expected:
```
Success! The configuration is valid.
```

```bash
terraform plan
```

Expected summary:
```
Plan: 4 to add, 0 to change, 0 to destroy.
```

The 4 resources:
- `random_string.suffix`
- `aws_security_group.rds`
- `aws_db_subnet_group.demo`
- `aws_db_instance.postgres`

---

## Step 5 — Apply

```bash
terraform apply -auto-approve
```

> RDS provisioning takes **5–10 minutes**. This is normal — AWS is allocating
> storage, configuring the parameter group, and running the first backup.

Expected output (abridged):
```
random_string.suffix: Creating...
random_string.suffix: Creation complete after 0s [id=xxxxxx]
aws_security_group.rds: Creating...
aws_security_group.rds: Creation complete after 2s
aws_db_subnet_group.demo: Creating...
aws_db_subnet_group.demo: Creation complete after 1s
aws_db_instance.postgres: Creating...
aws_db_instance.postgres: Still creating... [1m0s elapsed]
aws_db_instance.postgres: Still creating... [2m0s elapsed]
...
aws_db_instance.postgres: Creation complete after 7m42s

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

db_endpoint  = "terraform-028-postgres.czggqo0yyoe8.ap-south-1.rds.amazonaws.com:5432"
db_host      = "terraform-028-postgres.czggqo0yyoe8.ap-south-1.rds.amazonaws.com"
db_port      = 5432
db_name      = "robochefdb"
psql_connect = "psql -h terraform-028-postgres.czggqo0yyoe8.ap-south-1.rds.amazonaws.com -U robochef -d robochefdb -p 5432"
```

---

## Step 6 — Install psql client

```bash
sudo apt-get update -y && sudo apt-get install -y postgresql-client
```

Verify install:
```bash
psql --version
# psql (PostgreSQL) 14.x  (client version — connecting to server 16.14)
```

---

## Step 7 — Connect and verify

Grab the host from Terraform output:
```bash
DB_HOST=$(terraform output -raw db_host)
echo "Connecting to: $DB_HOST"
```

Connect with psql:
```bash
PGPASSWORD="Robochef2024!" psql \
  -h "$DB_HOST" \
  -U robochef \
  -d robochefdb \
  -p 5432
```

Inside the psql prompt, run:
```sql
SELECT version();
```

Live result:
```
                                                 version
---------------------------------------------------------------------------------------------------------
 PostgreSQL 16.14 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 9.4.0, 64-bit
(1 row)
```

Exit psql:
```sql
\q
```

---

## Key Concepts

### skip_final_snapshot = true
| Setting | Behaviour |
|---------|-----------|
| `true` | Destroy deletes the instance immediately — no snapshot required. Use in labs. |
| `false` (default) | Terraform forces you to set `final_snapshot_identifier` — required in production. |

### publicly_accessible = true
| Setting | When to use |
|---------|-------------|
| `true` | Demo / lab only. The DB gets a public DNS name and responds on port 5432 from any IP. |
| `false` | Production. Only resources inside the VPC (or via VPN/bastion) can connect. |

### Sensitive password
The `db_password` variable is marked `sensitive = true`. Terraform will never
print it in `plan` or `apply` output — it shows `(sensitive value)` instead.
In production, supply it via:
```bash
export TF_VAR_db_password="YourRealPassword"
# or use AWS Secrets Manager + data source
```

### Free-tier eligible combinations (db.t3.micro)
| Engine | Version | Free tier |
|--------|---------|-----------|
| postgres | 16.x | Yes |
| mysql | 8.0.x | Yes |
| mariadb | 10.x | Yes |

### Engine version check command
```bash
aws rds describe-db-engine-versions \
  --engine postgres \
  --region ap-south-1 \
  --query 'DBEngineVersions[*].EngineVersion' \
  --output text
```

---

## Step 8 — Destroy and clean up

```bash
terraform destroy -auto-approve
```

Expected (RDS destroy also takes a few minutes):
```
aws_db_instance.postgres: Destroying...
aws_db_instance.postgres: Still destroying... [1m0s elapsed]
...
aws_db_instance.postgres: Destruction complete after 3m15s
aws_db_subnet_group.demo: Destroying...
aws_db_subnet_group.demo: Destruction complete after 1s
aws_security_group.rds: Destroying...
aws_security_group.rds: Destruction complete after 1s
random_string.suffix: Destroying...
random_string.suffix: Destruction complete after 0s

Destroy complete! Resources: 4 destroyed.
```

Remove local Terraform cache:
```bash
rm -rf .terraform
```

---

## Copy-Paste Script (all steps in one)

Run this from your home directory to create the project, apply, verify, and destroy in one go.

```bash
#!/bin/bash
set -e

WORKDIR=~/terraform-aws-028-rds
mkdir -p "$WORKDIR" && cd "$WORKDIR"

# ── providers.tf ─────────────────────────────────────────────────────────────
cat > providers.tf <<'EOF_TF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
EOF_TF

# ── variables.tf ──────────────────────────────────────────────────────────────
cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "db_password" {
  description = "Master password for the RDS Postgres instance"
  type        = string
  sensitive   = true
  default     = "Robochef2024!"
}
EOF_TF

# ── main.tf ───────────────────────────────────────────────────────────────────
cat > main.tf <<'EOF_TF'
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "aws_security_group" "rds" {
  name        = "terraform-028-rds-sg"
  description = "Allow Postgres from anywhere (demo only)"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "terraform-028-rds-sg"
    Owner = "saravanans"
  }
}

resource "aws_db_subnet_group" "demo" {
  name       = "terraform-028-rds-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "postgres" {
  identifier        = "terraform-028-postgres"
  engine            = "postgres"
  engine_version    = "16.14"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "robochefdb"
  username = "robochef"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.demo.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  skip_final_snapshot = true
  publicly_accessible = true
  multi_az            = false

  tags = {
    Name    = "terraform-028-postgres"
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}
EOF_TF

# ── outputs.tf ────────────────────────────────────────────────────────────────
cat > outputs.tf <<'EOF_TF'
output "db_endpoint" {
  description = "Full RDS endpoint including port"
  value       = aws_db_instance.postgres.endpoint
}

output "db_host" {
  description = "RDS hostname (without port)"
  value       = aws_db_instance.postgres.address
}

output "db_port" {
  description = "RDS port"
  value       = aws_db_instance.postgres.port
}

output "db_name" {
  description = "Database name created inside the instance"
  value       = aws_db_instance.postgres.db_name
}

output "psql_connect" {
  description = "Ready-to-run psql command"
  value       = "psql -h ${aws_db_instance.postgres.address} -U robochef -d robochefdb -p 5432"
}
EOF_TF

terraform init
terraform fmt
terraform validate
terraform apply -auto-approve

echo ""
echo "=== Verifying with psql ==="
sudo apt-get install -y postgresql-client -q
DB_HOST=$(terraform output -raw db_host)
PGPASSWORD="Robochef2024!" psql -h "$DB_HOST" -U robochef -d robochefdb -p 5432 -c "SELECT version();"

echo ""
echo "=== Destroying ==="
terraform destroy -auto-approve
rm -rf .terraform
echo "Done — all resources destroyed and .terraform removed."
```

---

## Concept Summary

| Concept | Value used | Why |
|---------|-----------|-----|
| Engine | postgres 16.14 | 16.3 was not available in ap-south-1; always check first |
| Instance class | db.t3.micro | Free-tier eligible |
| Storage | 20 GB gp2 | Minimum for free tier |
| skip_final_snapshot | true | Allows clean destroy without naming a snapshot |
| publicly_accessible | true | Lab convenience — never use in production |
| multi_az | false | Single AZ keeps demo cost at zero |
| sensitive | true on db_password | Terraform hides the value from all output |
| recovery | No snapshot | Lab only; production should keep `skip_final_snapshot = false` |
