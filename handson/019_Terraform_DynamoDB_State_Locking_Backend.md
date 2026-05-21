# 019 — S3 + DynamoDB State Locking Backend for Terraform

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~30 minutes

## Topic

Lab 018 introduced the S3 remote backend — storing `terraform.tfstate` in S3 instead of on your local disk. That solved the "team can't share state" problem. But it left one problem open: **two engineers could run `terraform apply` at the same time**, both reading the same state file, both making changes, and one overwriting the other's work.

This lab adds **DynamoDB state locking** on top of the S3 backend. With locking enabled, Terraform writes a lock record to a DynamoDB table before touching state, and deletes it when done. If a second `terraform apply` starts while the first is still running, it reads that lock record and immediately fails with:

```text
Error acquiring the state lock
```

No data corruption. No silent overwrite. The second engineer knows someone is already running apply.

### What changes from 018 to 019

| Area | 018 (S3 only) | 019 (S3 + DynamoDB) |
|------|--------------|----------------------|
| State storage | S3 bucket | S3 bucket (same) |
| State locking | None — concurrent applies allowed | DynamoDB table — concurrent applies blocked |
| Bootstrap creates | S3 bucket + versioning | S3 bucket + versioning + DynamoDB table |
| `terraform init` flags | 3 (`bucket`, `key`, `region`) | 4 (`bucket`, `key`, `region`, `dynamodb_table`) |
| Cost | S3 storage only | S3 storage + DynamoDB PAY_PER_REQUEST |

### How DynamoDB locking works

When Terraform runs `plan`, `apply`, or `destroy`:

1. Terraform writes an item to DynamoDB — the `LockID` is `BUCKET/KEY` (no suffix). This is the **active lock**.
2. Terraform reads/writes state in S3.
3. Terraform deletes the DynamoDB item when the operation finishes.

After a successful apply, a **second item** is left behind permanently:

- `LockID` ends in `-md5`
- It stores a `Digest` field (MD5 hash of the state file)

This is a checksum record, not an active lock. It is normal and expected.

**What happens when a lock is held:**

```text
╔══════════════════════════════════════════════════════════╗
║             Error acquiring the state lock               ║
║                                                          ║
║  Lock Info:                                              ║
║    ID:        abc123...                                  ║
║    Path:      mybucket/mykey/terraform.tfstate           ║
║    Operation: OperationTypeApply                         ║
║    Who:       saravanans@chillbotindia.com               ║
║    Created:   2026-05-21 05:54:00 +0000 UTC              ║
║                                                          ║
║  Terraform acquires a state lock to protect the state    ║
║  from being written by multiple users at the same time.  ║
╚══════════════════════════════════════════════════════════╝
```

This lab uses a **two-phase bootstrap** pattern (same as 018):

- **Phase 1 — Bootstrap:** A separate Terraform project in `bootstrap/` creates the S3 bucket, enables versioning, and creates the DynamoDB table. Its own state stays local.
- **Phase 2 — Main project:** Uses the S3 bucket and DynamoDB table as backend. All its state lives in S3 with locking.

---

## What Gets Created

**Bootstrap phase (local state):**

```text
random_string.suffix              → 8-char random suffix for bucket name
aws_s3_bucket.tfstate             → terraform-019-tfstate-frrv9sh9
aws_s3_bucket_versioning.tfstate  → versioning enabled
aws_dynamodb_table.tflock         → terraform-019-state-lock
```

**Main project (remote state in S3):**

```text
aws_s3_bucket.app  → terraform-019-app-bucket-demo
```

**Live results from this lab:**

```text
State bucket:    terraform-019-tfstate-frrv9sh9
DynamoDB table:  terraform-019-state-lock
App bucket:      terraform-019-app-bucket-demo
State file:      2026-05-21 05:54:11  3067 terraform.tfstate
DynamoDB item:   LockID = terraform-019-tfstate-frrv9sh9/019-demo/terraform.tfstate-md5
                 Digest = <MD5 hash>
DynamoDB scan:   Count = 1
```

---

## 1. Create Project Folders

```bash
mkdir -p ~/terraform-019-demo/bootstrap
cd ~/terraform-019-demo
```

The layout you will end up with:

```text
terraform-019-demo/
├── bootstrap/
│   ├── main.tf              ← creates S3 bucket + DynamoDB table
│   ├── .terraform/
│   └── terraform.tfstate    ← LOCAL state for bootstrap
├── providers.tf             ← main project, backend "s3" {}
├── variables.tf
└── main.tf
```

---

## 2. Bootstrap Phase — Create S3 Bucket and DynamoDB Table

The bootstrap creates three AWS resources and produces two outputs. State for the bootstrap itself stays local (no backend block).

### 2a. Write bootstrap/main.tf

```bash
cat > ~/terraform-019-demo/bootstrap/main.tf <<'EOF_TF'
terraform {
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}

provider "aws" { region = "ap-south-1" }

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "aws_s3_bucket" "tfstate" {
  bucket        = "terraform-019-tfstate-${random_string.suffix.result}"
  force_destroy = true
  tags          = { Name = "terraform-019-state-bucket" }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_dynamodb_table" "tflock" {
  name         = "terraform-019-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = { Name = "terraform-019-state-lock" }
}

output "bucket_name"    { value = aws_s3_bucket.tfstate.bucket }
output "dynamodb_table" { value = aws_dynamodb_table.tflock.name }
EOF_TF
```

### Key concepts in bootstrap/main.tf

**`billing_mode = "PAY_PER_REQUEST"`**

DynamoDB has two billing modes:

| Mode | What it means |
|------|--------------|
| `PROVISIONED` | You declare read/write capacity units per second. Costs money even at zero traffic. |
| `PAY_PER_REQUEST` | No pre-provisioned capacity. You pay only when Terraform writes a lock item. For state locking, traffic is extremely low — this is always the right choice. |

**`hash_key = "LockID"`**

DynamoDB requires a partition key (hash key). Terraform's S3 backend hard-codes the partition key name as `LockID`. You must use exactly this name — no other value will work.

**`attribute` block**

You only declare attributes that are part of keys. Since `LockID` is the only key, only one `attribute` block is needed. Other fields Terraform writes (like `Digest` and lock metadata) are added dynamically — you do not declare them in the schema.

---

### 2b. Run Bootstrap

```bash
cd ~/terraform-019-demo/bootstrap

terraform init
```

Expected:

```text
- Installing hashicorp/aws v6.x.x...
- Installing hashicorp/random v3.x.x...

Terraform has been successfully initialized!
```

```bash
terraform apply
```

Type `yes`.

Expected output:

```text
random_string.suffix: Creating...
random_string.suffix: Creation complete after 0s [id=frrv9sh9]

aws_s3_bucket.tfstate: Creating...
aws_dynamodb_table.tflock: Creating...
aws_s3_bucket.tfstate: Creation complete after 2s [id=terraform-019-tfstate-frrv9sh9]
aws_s3_bucket_versioning.tfstate: Creating...
aws_dynamodb_table.tflock: Creation complete after 8s [id=terraform-019-state-lock]
aws_s3_bucket_versioning.tfstate: Creation complete after 1s

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

bucket_name    = "terraform-019-tfstate-frrv9sh9"
dynamodb_table = "terraform-019-state-lock"
```

Note your bucket name — you will need it in the next step. The random suffix makes it globally unique.

```bash
# Save the bucket name for use in later commands
BUCKET=$(terraform output -raw bucket_name)
echo "Bucket: $BUCKET"
```

---

### 2c. Verify DynamoDB Table

```bash
aws dynamodb describe-table \
  --table-name terraform-019-state-lock \
  --region ap-south-1 \
  --query "Table.{Status:TableStatus,BillingMode:BillingModeSummary.BillingMode,HashKey:KeySchema[0].AttributeName}" \
  --output table
```

Expected:

```text
-----------------------------------------
|           DescribeTable               |
+------------+--------------------------+
|  BillingMode| PAY_PER_REQUEST         |
|  HashKey   | LockID                   |
|  Status    | ACTIVE                   |
+------------+--------------------------+
```

Verify the table is empty (no lock items yet):

```bash
aws dynamodb scan \
  --table-name terraform-019-state-lock \
  --region ap-south-1
```

Expected:

```text
{
    "Items": [],
    "Count": 0,
    "ScannedCount": 0,
    ...
}
```

---

## 3. Main Project — Configure S3 + DynamoDB Backend

### 3a. Write providers.tf

```bash
cat > ~/terraform-019-demo/providers.tf <<'EOF_TF'
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }

  backend "s3" {}
}

provider "aws" { region = var.aws_region }
EOF_TF
```

The `backend "s3" {}` block is intentionally empty. All values are passed at `terraform init` time using `-backend-config` flags. This pattern lets you use the same Terraform code with different backends (e.g., different environments) without changing any files.

### 3b. Write variables.tf

```bash
cat > ~/terraform-019-demo/variables.tf <<'EOF_TF'
variable "aws_region" {
  type    = string
  default = "ap-south-1"
}
EOF_TF
```

### 3c. Write main.tf

```bash
cat > ~/terraform-019-demo/main.tf <<'EOF_TF'
resource "aws_s3_bucket" "app" {
  bucket        = "terraform-019-app-bucket-demo"
  force_destroy = true
  tags          = { Name = "terraform-019-app" }
}

output "app_bucket_name" { value = aws_s3_bucket.app.bucket }
output "state_backend"   { value = "s3 + dynamodb locking" }
EOF_TF
```

---

## 4. Initialize Main Project with All 4 Backend Flags

The `terraform init` command for an S3 backend with DynamoDB locking requires four flags:

```bash
cd ~/terraform-019-demo

terraform init \
  -backend-config="bucket=terraform-019-tfstate-frrv9sh9" \
  -backend-config="key=019-demo/terraform.tfstate" \
  -backend-config="region=ap-south-1" \
  -backend-config="dynamodb_table=terraform-019-state-lock"
```

Replace `terraform-019-tfstate-frrv9sh9` with your actual bucket name from the bootstrap output.

Or use the shell variable saved earlier:

```bash
cd ~/terraform-019-demo

terraform init \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="key=019-demo/terraform.tfstate" \
  -backend-config="region=ap-south-1" \
  -backend-config="dynamodb_table=terraform-019-state-lock"
```

**What each flag does:**

| Flag | Value | Purpose |
|------|-------|---------|
| `bucket` | `terraform-019-tfstate-frrv9sh9` | S3 bucket that stores the state file |
| `key` | `019-demo/terraform.tfstate` | Path inside the bucket where state is stored |
| `region` | `ap-south-1` | AWS region for both S3 and DynamoDB |
| `dynamodb_table` | `terraform-019-state-lock` | DynamoDB table used for locking |

Expected output:

```text
Initializing the backend...

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Installing hashicorp/aws v6.x.x...

Terraform has been successfully initialized!
```

---

## 5. Validate and Plan

```bash
cd ~/terraform-019-demo

terraform validate
```

Expected:

```text
Success! The configuration is valid.
```

```bash
terraform plan
```

Expected plan:

```text
Terraform will perform the following actions:

  # aws_s3_bucket.app will be created
  + resource "aws_s3_bucket" "app" {
      + bucket        = "terraform-019-app-bucket-demo"
      + force_destroy = true
      + tags          = {
          + "Name" = "terraform-019-app"
        }
    }

Plan: 1 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + app_bucket_name = "terraform-019-app-bucket-demo"
  + state_backend   = "s3 + dynamodb locking"
```

---

## 6. Apply and Verify Locking

```bash
terraform apply
```

Type `yes`.

Expected output:

```text
aws_s3_bucket.app: Creating...
aws_s3_bucket.app: Creation complete after 2s [id=terraform-019-app-bucket-demo]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

app_bucket_name = "terraform-019-app-bucket-demo"
state_backend   = "s3 + dynamodb locking"
```

---

## 7. Verify State in S3

```bash
aws s3 ls s3://terraform-019-tfstate-frrv9sh9/019-demo/
```

Expected (matches live result):

```text
2026-05-21 05:54:11       3067 terraform.tfstate
```

The state file is stored remotely. Your local project folder has no `terraform.tfstate` file.

```bash
ls -la ~/terraform-019-demo/
```

Expected — no `terraform.tfstate` here:

```text
-rw-rw-r-- 1 saravanans saravanans  143 May 21 05:53 main.tf
-rw-rw-r-- 1 saravanans saravanans  202 May 21 05:52 providers.tf
-rw-rw-r-- 1 saravanans saravanans   58 May 21 05:52 variables.tf
drwxrwxr-x 3 saravanans saravanans 4096 May 21 05:53 .terraform/
-rw-r--r-- 1 saravanans saravanans 1234 May 21 05:53 .terraform.lock.hcl
```

---

## 8. Inspect the DynamoDB Table After Apply

After `terraform apply` completes, scan the DynamoDB table:

```bash
aws dynamodb scan \
  --table-name terraform-019-state-lock \
  --region ap-south-1
```

Expected (matches live result):

```text
{
    "Items": [
        {
            "Digest": {
                "S": "d41d8cd98f00b204e9800998ecf8427e"
            },
            "LockID": {
                "S": "terraform-019-tfstate-frrv9sh9/019-demo/terraform.tfstate-md5"
            }
        }
    ],
    "Count": 1,
    "ScannedCount": 1,
    ...
}
```

**What this item is:**

| Field | Value | Meaning |
|-------|-------|---------|
| `LockID` | `...terraform.tfstate-md5` | Ends in `-md5` — this is the checksum record |
| `Digest` | MD5 hash string | MD5 of the current state file in S3 |

This is **not an active lock**. This is a permanent checksum record that Terraform uses to detect state corruption. It persists between operations. Count = 1 is the expected normal state.

### Active lock vs. MD5 checksum record

| Item | LockID ends in | Present when | Contains |
|------|---------------|-------------|----------|
| Active lock | (nothing — just the path) | Only during a running apply/plan/destroy | Operation type, who started it, timestamp |
| Checksum record | `-md5` | Always, after first apply | `Digest` = MD5 of state |

**Example of an active lock item** (what you would see if you scanned DynamoDB while `terraform apply` was running in another terminal):

```json
{
    "Items": [
        {
            "LockID": {
                "S": "terraform-019-tfstate-frrv9sh9/019-demo/terraform.tfstate"
            },
            "Info": {
                "S": "{\"ID\":\"abc123-...\",\"Operation\":\"OperationTypeApply\",\"Who\":\"saravanans@robochef.co\",\"Version\":\"1.x.x\",\"Created\":\"2026-05-21T05:54:00Z\",\"Path\":\"terraform-019-tfstate-frrv9sh9/019-demo/terraform.tfstate\"}"
            }
        },
        {
            "LockID": {
                "S": "terraform-019-tfstate-frrv9sh9/019-demo/terraform.tfstate-md5"
            },
            "Digest": {
                "S": "d41d8cd98f00b204e9800998ecf8427e"
            }
        }
    ],
    "Count": 2
}
```

When Count = 2 and one item has no `-md5` suffix, an operation is in progress. When Count = 1 and the only item ends in `-md5`, the table is in its resting state — all is well.

---

## 9. Simulate What State Locking Prevents

To understand the value of locking, consider this sequence without it:

```text
Engineer A (saravanans@robochef.co):      terraform apply  ← starts, reads state
Engineer B (team@chillbotindia.com):      terraform apply  ← starts, also reads same state
Engineer A: creates resource X            ← writes updated state
Engineer B: creates resource Y            ← writes updated state, OVERWRITES A's state
```

Result: resource X disappears from state — Terraform no longer knows it exists. The next apply will try to create it again, possibly failing with "resource already exists."

With DynamoDB locking:

```text
Engineer A: terraform apply  ← acquires lock, writes lock item to DynamoDB
Engineer B: terraform apply  ← reads DynamoDB, finds active lock item, immediately fails:

Error acquiring the state lock
Lock Info:
  Who: saravanans@robochef.co
  Created: 2026-05-21 05:54:00 +0000 UTC

Engineer B waits, then re-runs after Engineer A finishes.
```

No corruption. No silent overwrite.

---

## 10. Destroy Sequence

Always destroy the main project first, then the bootstrap. Destroying bootstrap first would delete the S3 bucket and DynamoDB table while the main project still references them.

### Step 1 — Destroy main project

```bash
cd ~/terraform-019-demo
terraform destroy
```

Type `yes`.

Expected:

```text
aws_s3_bucket.app: Destroying...
aws_s3_bucket.app: Destruction complete after 1s

Destroy complete! Resources: 1 destroyed.
```

After destroy, verify the state file is still in S3 (destroy updates the state, not deletes it):

```bash
aws s3 ls s3://terraform-019-tfstate-frrv9sh9/019-demo/
```

The state file still exists but now shows 0 resources managed.

### Step 2 — Clean up main project Terraform files

```bash
cd ~/terraform-019-demo
rm -rf .terraform
```

This removes the cached provider plugins and backend configuration. Always do this before destroying the bootstrap — otherwise Terraform would try to reach the now-deleted backend.

### Step 3 — Destroy bootstrap

```bash
cd ~/terraform-019-demo/bootstrap
terraform destroy
```

Type `yes`.

Expected:

```text
aws_s3_bucket_versioning.tfstate: Destroying...
aws_s3_bucket_versioning.tfstate: Destruction complete after 1s
aws_dynamodb_table.tflock: Destroying...
aws_s3_bucket.tfstate: Destroying...
aws_dynamodb_table.tflock: Destruction complete after 8s
aws_s3_bucket.tfstate: Destruction complete after 2s
random_string.suffix: Destroying...
random_string.suffix: Destruction complete after 0s

Destroy complete! Resources: 4 destroyed.
```

### Step 4 — Clean up bootstrap Terraform files

```bash
cd ~/terraform-019-demo/bootstrap
rm -rf .terraform
```

### Verify cleanup

```bash
# DynamoDB table gone
aws dynamodb list-tables --region ap-south-1 | grep terraform-019

# S3 bucket gone
aws s3 ls | grep terraform-019

# App bucket gone
aws s3 ls | grep terraform-019-app
```

All commands should return no output.

---

## 11. Full Copy-Paste Setup

```bash
mkdir -p ~/terraform-019-demo/bootstrap
cd ~/terraform-019-demo/bootstrap

cat > main.tf <<'EOF_TF'
terraform {
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}

provider "aws" { region = "ap-south-1" }

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "aws_s3_bucket" "tfstate" {
  bucket        = "terraform-019-tfstate-${random_string.suffix.result}"
  force_destroy = true
  tags          = { Name = "terraform-019-state-bucket" }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_dynamodb_table" "tflock" {
  name         = "terraform-019-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = { Name = "terraform-019-state-lock" }
}

output "bucket_name"    { value = aws_s3_bucket.tfstate.bucket }
output "dynamodb_table" { value = aws_dynamodb_table.tflock.name }
EOF_TF

terraform init
terraform apply -auto-approve

BUCKET=$(terraform output -raw bucket_name)
echo "Bucket: $BUCKET"

cd ~/terraform-019-demo

cat > providers.tf <<'EOF_TF'
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }

  backend "s3" {}
}

provider "aws" { region = var.aws_region }
EOF_TF

cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  type    = string
  default = "ap-south-1"
}
EOF_TF

cat > main.tf <<'EOF_TF'
resource "aws_s3_bucket" "app" {
  bucket        = "terraform-019-app-bucket-demo"
  force_destroy = true
  tags          = { Name = "terraform-019-app" }
}

output "app_bucket_name" { value = aws_s3_bucket.app.bucket }
output "state_backend"   { value = "s3 + dynamodb locking" }
EOF_TF

terraform init \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="key=019-demo/terraform.tfstate" \
  -backend-config="region=ap-south-1" \
  -backend-config="dynamodb_table=terraform-019-state-lock"

terraform validate
terraform plan
```

Then apply:

```bash
terraform apply
```

---

## 12. 018 vs. 019 Comparison

| Feature | 018 (S3 backend only) | 019 (S3 + DynamoDB) |
|---------|-----------------------|----------------------|
| State storage location | S3 | S3 |
| State versioning | Enabled | Enabled |
| Concurrent apply protection | None | DynamoDB lock |
| Bootstrap creates | S3 bucket, versioning | S3 bucket, versioning, DynamoDB table |
| `terraform init` backend flags | 3 | 4 (adds `dynamodb_table`) |
| Lock acquired at | — | Start of plan/apply/destroy |
| Lock released at | — | End of operation |
| Checksum record in DynamoDB | — | Yes (`-md5` item) |
| DynamoDB billing | — | `PAY_PER_REQUEST` |
| Good for solo work | Yes | Yes |
| Good for team work | Risky — no locking | Yes — safe |

---

## 13. Common Errors

### Error: NoSuchBucket

```text
Error: Failed to get existing workspaces: S3 bucket does not exist.
```

Cause: the bootstrap was not applied yet, or you used the wrong bucket name in `-backend-config`.

Fix: confirm the bucket exists:

```bash
aws s3 ls | grep terraform-019
```

Re-run bootstrap apply if needed, then re-run `terraform init` with the correct bucket name.

---

### Error: ResourceNotFoundException (DynamoDB)

```text
Error: Error acquiring the state lock:
  ResourceNotFoundException: Requested resource not found
```

Cause: the `dynamodb_table` flag points to a table that does not exist, or it was not yet created by bootstrap.

Fix: confirm the table exists:

```bash
aws dynamodb list-tables --region ap-south-1
```

---

### Error: BucketAlreadyExists or BucketAlreadyOwnedByYou

```text
Error: creating Amazon S3 Bucket: BucketAlreadyOwnedByYou
```

Cause: you ran bootstrap twice and the bucket name from the first run still exists.

Fix: destroy the first bootstrap before re-running:

```bash
cd ~/terraform-019-demo/bootstrap
terraform destroy
```

Then apply again.

---

### Stale lock — Error acquiring state lock

```text
Error acquiring the state lock
```

Cause: a previous `terraform apply` was interrupted (Ctrl+C, VM shutdown) and left an active lock item in DynamoDB.

Fix — force-unlock (use with care):

```bash
terraform force-unlock LOCK_ID
```

Get the `LOCK_ID` from the error message, or by scanning DynamoDB for items without `-md5` suffix.

---

### Error: InvalidBucketName after re-init

```text
Error: Invalid bucket name
```

Cause: you ran `terraform init` without `-backend-config` flags, or used an empty backend. Re-run with all four flags.

---

## 14. Concept Summary

| Concept | What It Means |
|---------|--------------|
| `backend "s3" {}` | Empty backend block — all config passed via `-backend-config` flags at init time |
| `dynamodb_table` backend flag | Name of the DynamoDB table to use for locking — must match the table created in bootstrap |
| `LockID` | The partition key DynamoDB requires. Terraform's S3 backend hard-codes this exact name |
| `PAY_PER_REQUEST` billing | No capacity to provision. Pay only per request. Correct for state locking traffic |
| Active lock item | Written to DynamoDB at start of any Terraform operation. Deleted when done. `LockID` = bucket/key |
| `-md5` suffix item | Permanent checksum record. Written after every successful apply. `Digest` = MD5 of state file |
| `Count = 1` after apply | Expected resting state — only the checksum record exists, no active lock |
| `Count = 2` during apply | Active lock + checksum — a Terraform operation is in progress |
| `force-unlock` | Emergency command to manually delete a stale lock. Use only when you are certain no operation is running |
| Two-phase bootstrap | Create the backend infrastructure first (local state), then configure main project to use it (remote state) |
| `rm -rf .terraform` | Remove cached backend config before destroying bootstrap — prevents Terraform from trying to reach a deleted backend |
