# 024 — Terraform AWS IAM Users, Roles & Policies

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~20 minutes

## Topic

Every AWS resource you create — an EC2 instance, a Lambda function, an S3 bucket — needs a clear answer to two questions: **who is allowed to use it**, and **what are they allowed to do?** AWS Identity and Access Management (IAM) is the service that answers both questions.

IAM has four building blocks:

| Concept | What It Is |
|---|---|
| **User** | A human identity with long-term credentials (username/password, access keys) |
| **Group** | A collection of users that share the same permissions |
| **Policy** | A JSON document that defines what actions are allowed or denied on which resources |
| **Role** | An identity that AWS services (or other accounts) can **assume** to get temporary credentials |

The most important design principle in IAM is the **Principle of Least Privilege**: every identity — user, role, or service — should have the minimum permissions needed to do its job, and nothing more. Grant `s3:GetObject` if you only need to read files. Do not grant `s3:*` just because it is convenient.

This lab uses Terraform to create a complete IAM setup for the `robochef.co` project:

- An IAM user (`saravanans-demo-user`) added to a group
- A group (`robochef-demo-group`) with a custom S3 read-only policy attached
- A custom IAM policy (`robochef-s3-read-only`) with least-privilege S3 permissions
- An IAM role (`robochef-ec2-demo-role`) that EC2 instances can assume
- An AWS managed policy (`ReadOnlyAccess`) attached to the role
- An instance profile (`robochef-ec2-instance-profile`) so EC2 can use the role

**Plan: 8 to add, 0 to change, 0 to destroy.**

---

## Architecture

```
User: saravanans-demo-user
  └── Group: robochef-demo-group
        └── Policy: robochef-s3-read-only (S3 List/Get)

Role: robochef-ec2-demo-role
  ├── Trust policy: ec2.amazonaws.com can assume
  ├── Policy: AWS managed ReadOnlyAccess
  └── Instance Profile: robochef-ec2-instance-profile
```

The **trust policy** on the role answers: *who can assume this role?* In this lab, the EC2 service (`ec2.amazonaws.com`) can assume it. The **permission policies** attached to the role answer: *what can the role do once assumed?* Here, the role gets AWS managed `ReadOnlyAccess`.

The **instance profile** is a thin wrapper required by EC2. You cannot attach a role directly to an EC2 instance — you must first wrap the role in an `aws_iam_instance_profile` and then specify the profile name at instance launch.

---

## What Terraform Creates

```text
aws_iam_user.demo                           → saravanans-demo-user
aws_iam_group.demo                          → robochef-demo-group
aws_iam_group_membership.demo               → adds user to group
aws_iam_policy.s3_read                      → robochef-s3-read-only (custom policy)
aws_iam_group_policy_attachment.s3_read     → attaches custom policy to group
aws_iam_role.ec2_role                       → robochef-ec2-demo-role
aws_iam_role_policy_attachment.readonly     → attaches AWS managed ReadOnlyAccess to role
aws_iam_instance_profile.ec2                → robochef-ec2-instance-profile
```

**Plan: 8 to add, 0 to change, 0 to destroy.**

---

## 1. Create Project Folder

```bash
mkdir -p ~/terraform-iam-024
cd ~/terraform-iam-024
```

---

## 2. Check Your AWS Credentials

```bash
aws sts get-caller-identity
aws configure get region
```

The live test for this lab ran in `ap-south-1`. IAM is a **global service** — users, groups, roles, and policies are not region-specific. However, the AWS provider still requires a region to be configured for API calls.

---

## 3. Create Terraform Files

Create the following five files:

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
  default = "ap-south-1"
}
variable "username" {
  type    = string
  default = "saravanans-demo-user"
}
EOF_TF
```

Two variables: the AWS region for the provider, and the IAM username. Everything else — group names, role names, policy names — is hard-coded in `main.tf` because they are specific to the `robochef.co` project.

---

## 6. main.tf

```bash
cat > main.tf <<'EOF_TF'
data "aws_caller_identity" "current" {}

resource "aws_iam_user" "demo" {
  name = var.username
  tags = { Owner = "saravanans", Project = "robochef.co" }
}

resource "aws_iam_group" "demo" {
  name = "robochef-demo-group"
}

resource "aws_iam_group_membership" "demo" {
  name  = "robochef-demo-membership"
  group = aws_iam_group.demo.name
  users = [aws_iam_user.demo.name]
}

resource "aws_iam_policy" "s3_read" {
  name        = "robochef-s3-read-only"
  description = "Allow S3 ListBucket and GetObject"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListAllMyBuckets", "s3:GetObject", "s3:ListBucket"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_group_policy_attachment" "s3_read" {
  group      = aws_iam_group.demo.name
  policy_arn = aws_iam_policy.s3_read.arn
}

resource "aws_iam_role" "ec2_role" {
  name = "robochef-ec2-demo-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Owner = "saravanans", Site = "chillbotindia.com" }
}

resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "robochef-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}
EOF_TF
```

**Key connections in main.tf:**

```text
aws_iam_user.demo.name              → aws_iam_group_membership.demo (users list)
aws_iam_group.demo.name             → aws_iam_group_membership.demo (group)
aws_iam_group.demo.name             → aws_iam_group_policy_attachment.s3_read (group)
aws_iam_policy.s3_read.arn          → aws_iam_group_policy_attachment.s3_read (policy_arn)
aws_iam_role.ec2_role.name          → aws_iam_role_policy_attachment.readonly (role)
aws_iam_role.ec2_role.name          → aws_iam_instance_profile.ec2 (role)
```

---

## 7. outputs.tf

```bash
cat > outputs.tf <<'EOF_TF'
output "user_arn"              { value = aws_iam_user.demo.arn }
output "group_name"            { value = aws_iam_group.demo.name }
output "custom_policy_arn"     { value = aws_iam_policy.s3_read.arn }
output "role_arn"              { value = aws_iam_role.ec2_role.arn }
output "instance_profile_name" { value = aws_iam_instance_profile.ec2.name }
EOF_TF
```

---

## 8. terraform.tfvars

```bash
cat > terraform.tfvars <<'EOF_TF'
aws_region = "ap-south-1"
username   = "saravanans-demo-user"
EOF_TF
```

Update `aws_region` to match your configured AWS region if different.

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
# aws_iam_user.demo will be created
  + resource "aws_iam_user" "demo" {
      + name = "saravanans-demo-user"
      + tags = { "Owner" = "saravanans", "Project" = "robochef.co" }
    }

# aws_iam_group.demo will be created
  + resource "aws_iam_group" "demo" {
      + name = "robochef-demo-group"
    }

# aws_iam_group_membership.demo will be created
# aws_iam_policy.s3_read will be created
# aws_iam_group_policy_attachment.s3_read will be created
# aws_iam_role.ec2_role will be created
  + resource "aws_iam_role" "ec2_role" {
      + name = "robochef-ec2-demo-role"
      + tags = { "Owner" = "saravanans", "Site" = "chillbotindia.com" }
    }

# aws_iam_role_policy_attachment.readonly will be created
# aws_iam_instance_profile.ec2 will be created

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
aws_iam_user.demo: Creating...
aws_iam_group.demo: Creating...
aws_iam_policy.s3_read: Creating...
aws_iam_role.ec2_role: Creating...
aws_iam_user.demo: Creation complete after 1s [id=saravanans-demo-user]
aws_iam_group.demo: Creation complete after 1s [id=robochef-demo-group]
aws_iam_policy.s3_read: Creation complete after 1s [id=arn:aws:iam::043000359118:policy/robochef-s3-read-only]
aws_iam_role.ec2_role: Creation complete after 1s [id=robochef-ec2-demo-role]
aws_iam_group_membership.demo: Creating...
aws_iam_group_policy_attachment.s3_read: Creating...
aws_iam_role_policy_attachment.readonly: Creating...
aws_iam_instance_profile.ec2: Creating...
aws_iam_group_membership.demo: Creation complete after 0s
aws_iam_group_policy_attachment.s3_read: Creation complete after 0s
aws_iam_role_policy_attachment.readonly: Creation complete after 0s
aws_iam_instance_profile.ec2: Creation complete after 1s [id=robochef-ec2-instance-profile]

Apply complete! Resources: 8 added, 0 changed, 0 destroyed.

Outputs:

custom_policy_arn     = "arn:aws:iam::043000359118:policy/robochef-s3-read-only"
group_name            = "robochef-demo-group"
instance_profile_name = "robochef-ec2-instance-profile"
role_arn              = "arn:aws:iam::043000359118:role/robochef-ec2-demo-role"
user_arn              = "arn:aws:iam::043000359118:user/saravanans-demo-user"
```

**Creation order Terraform used:**

1. `aws_iam_user.demo`, `aws_iam_group.demo`, `aws_iam_policy.s3_read`, and `aws_iam_role.ec2_role` are created in parallel — none depends on the others
2. `aws_iam_group_membership.demo`, `aws_iam_group_policy_attachment.s3_read`, `aws_iam_role_policy_attachment.readonly`, and `aws_iam_instance_profile.ec2` are created in parallel after step 1 completes

---

## 13. Verify with AWS CLI

### Confirm the user exists

```bash
aws iam get-user --user-name saravanans-demo-user
```

Expected output:

```json
{
    "User": {
        "UserName": "saravanans-demo-user",
        "UserId": "AIDA...",
        "Arn": "arn:aws:iam::043000359118:user/saravanans-demo-user",
        "Path": "/",
        "CreateDate": "2026-05-21T...",
        "Tags": [
            { "Key": "Owner",   "Value": "saravanans" },
            { "Key": "Project", "Value": "robochef.co" }
        ]
    }
}
```

### List the user's groups

```bash
aws iam list-groups-for-user --user-name saravanans-demo-user
```

Expected output:

```json
{
    "Groups": [
        {
            "GroupName": "robochef-demo-group",
            "GroupId": "AGPA...",
            "Arn": "arn:aws:iam::043000359118:group/robochef-demo-group"
        }
    ]
}
```

### Check policies attached to the group

```bash
aws iam list-attached-group-policies --group-name robochef-demo-group
```

Expected output:

```json
{
    "AttachedPolicies": [
        {
            "PolicyName": "robochef-s3-read-only",
            "PolicyArn": "arn:aws:iam::043000359118:policy/robochef-s3-read-only"
        }
    ]
}
```

### Inspect the role and its trust policy

```bash
aws iam get-role --role-name robochef-ec2-demo-role
```

Expected output (trust policy section):

```json
{
    "Role": {
        "RoleName": "robochef-ec2-demo-role",
        "Arn": "arn:aws:iam::043000359118:role/robochef-ec2-demo-role",
        "AssumeRolePolicyDocument": {
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": { "Service": "ec2.amazonaws.com" },
                "Action": "sts:AssumeRole"
            }]
        },
        "Tags": [
            { "Key": "Owner", "Value": "saravanans" },
            { "Key": "Site",  "Value": "chillbotindia.com" }
        ]
    }
}
```

The `AssumeRolePolicyDocument` is the **trust policy** — it confirms that `ec2.amazonaws.com` is the only principal allowed to assume this role.

---

## Concept: assume_role_policy (Trust Policy)

Every IAM role has two completely separate policy documents:

```text
assume_role_policy  →  WHO can call sts:AssumeRole to get temporary credentials
permission policies →  WHAT the role can do once it has been assumed
```

In `main.tf`, the trust policy is:

```hcl
assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect    = "Allow"
    Principal = { Service = "ec2.amazonaws.com" }
    Action    = "sts:AssumeRole"
  }]
})
```

This says: only the EC2 service is allowed to assume this role. A Lambda function, a human user, or another AWS account cannot assume it unless explicitly added to this trust policy.

The permission boundary (what the role can actually do) is set separately via `aws_iam_role_policy_attachment`, which attaches the AWS managed `ReadOnlyAccess` policy.

---

## Concept: aws_iam_instance_profile

EC2 instances do not accept IAM roles directly. They accept **instance profiles**. An instance profile is a container that holds exactly one IAM role and makes it available to EC2 at launch time.

```hcl
resource "aws_iam_instance_profile" "ec2" {
  name = "robochef-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}
```

When you launch an EC2 instance, you specify:

```hcl
iam_instance_profile = aws_iam_instance_profile.ec2.name
```

The instance then has access to the role's temporary credentials via the EC2 metadata service (`http://169.254.169.254/latest/meta-data/iam/...`). The AWS SDK and CLI inside the instance pick these credentials up automatically — no access keys stored on disk.

---

## Concept: jsonencode vs AWS Managed Policy ARN

This lab shows both ways to attach permissions to an IAM role or group.

**Custom policy via jsonencode:**

```hcl
resource "aws_iam_policy" "s3_read" {
  name   = "robochef-s3-read-only"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListAllMyBuckets", "s3:GetObject", "s3:ListBucket"]
      Resource = "*"
    }]
  })
}
```

`jsonencode` converts a Terraform object (HCL map/list) into a JSON string at apply time. This keeps policy documents readable in HCL without needing a separate `.json` file or heredoc.

**AWS managed policy via ARN:**

```hcl
resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
```

AWS pre-creates hundreds of managed policies. Their ARNs start with `arn:aws:iam::aws:policy/` (note: no account ID). They are maintained by AWS and updated when new services are released. Use them for broad, well-known permission sets. Use custom policies when you need fine-grained, least-privilege control.

| | Custom Policy | AWS Managed Policy |
|---|---|---|
| Defined in | Your Terraform code | AWS (pre-built) |
| ARN prefix | `arn:aws:iam::043000359118:policy/` | `arn:aws:iam::aws:policy/` |
| Least privilege | You control exactly | AWS decides scope |
| Updates | You manage | AWS maintains |
| Example | `robochef-s3-read-only` | `ReadOnlyAccess` |

---

## Warning: No Access Keys Are Created

This lab creates an IAM user but does **not** create access keys for that user. An IAM user with no access keys and no console password has no way to authenticate to AWS — the user exists in IAM but cannot make any API calls or log in to the console.

Access keys are sensitive credentials (equivalent to a username and password). Terraform can create them with `aws_iam_access_key`, but the secret key would then be stored in plaintext in `terraform.tfstate`. For this reason, access key creation is intentionally excluded from this lab.

In production, use IAM roles (not user access keys) wherever possible — for EC2 instances, Lambda functions, ECS tasks, and CI/CD pipelines.

---

## 14. Destroy

After the demo, remove all AWS resources:

```bash
terraform destroy
```

Type `yes`.

Expected:

```text
aws_iam_group_membership.demo: Destroying...
aws_iam_group_policy_attachment.s3_read: Destroying...
aws_iam_role_policy_attachment.readonly: Destroying...
aws_iam_instance_profile.ec2: Destroying...
aws_iam_group_membership.demo: Destruction complete after 0s
aws_iam_group_policy_attachment.s3_read: Destruction complete after 1s
aws_iam_role_policy_attachment.readonly: Destruction complete after 1s
aws_iam_instance_profile.ec2: Destruction complete after 1s
aws_iam_user.demo: Destroying...
aws_iam_group.demo: Destroying...
aws_iam_policy.s3_read: Destroying...
aws_iam_role.ec2_role: Destroying...
aws_iam_user.demo: Destruction complete after 1s
aws_iam_group.demo: Destruction complete after 1s
aws_iam_policy.s3_read: Destruction complete after 1s
aws_iam_role.ec2_role: Destruction complete after 1s

Destroy complete! Resources: 8 destroyed.
```

Then clean up the provider cache:

```bash
rm -rf .terraform
```

---

## Full Copy-Paste Setup Script

```bash
mkdir -p ~/terraform-iam-024
cd ~/terraform-iam-024

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
  default = "ap-south-1"
}
variable "username" {
  type    = string
  default = "saravanans-demo-user"
}
EOF_TF

cat > main.tf <<'EOF_TF'
data "aws_caller_identity" "current" {}

resource "aws_iam_user" "demo" {
  name = var.username
  tags = { Owner = "saravanans", Project = "robochef.co" }
}

resource "aws_iam_group" "demo" {
  name = "robochef-demo-group"
}

resource "aws_iam_group_membership" "demo" {
  name  = "robochef-demo-membership"
  group = aws_iam_group.demo.name
  users = [aws_iam_user.demo.name]
}

resource "aws_iam_policy" "s3_read" {
  name        = "robochef-s3-read-only"
  description = "Allow S3 ListBucket and GetObject"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListAllMyBuckets", "s3:GetObject", "s3:ListBucket"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_group_policy_attachment" "s3_read" {
  group      = aws_iam_group.demo.name
  policy_arn = aws_iam_policy.s3_read.arn
}

resource "aws_iam_role" "ec2_role" {
  name = "robochef-ec2-demo-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Owner = "saravanans", Site = "chillbotindia.com" }
}

resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "robochef-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}
EOF_TF

cat > outputs.tf <<'EOF_TF'
output "user_arn"              { value = aws_iam_user.demo.arn }
output "group_name"            { value = aws_iam_group.demo.name }
output "custom_policy_arn"     { value = aws_iam_policy.s3_read.arn }
output "role_arn"              { value = aws_iam_role.ec2_role.arn }
output "instance_profile_name" { value = aws_iam_instance_profile.ec2.name }
EOF_TF

cat > terraform.tfvars <<'EOF_TF'
aws_region = "ap-south-1"
username   = "saravanans-demo-user"
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
| `aws_iam_user` | Creates a human identity in IAM with a name and optional tags; no credentials are created unless explicitly added |
| `aws_iam_group` | Creates a named collection of users; policies attached to the group apply to all members |
| `aws_iam_group_membership` | Manages which users belong to a group; Terraform tracks this as a separate resource so it can add/remove members independently |
| `aws_iam_policy` | Creates a standalone customer-managed policy from a JSON document; can be attached to users, groups, or roles |
| `aws_iam_role` | Creates an IAM role with a trust policy that defines which principal (service, account, or user) can assume it |
| `trust policy` | The `assume_role_policy` on a role — controls WHO can call `sts:AssumeRole`; separate from what the role is allowed to do |
| `aws_iam_instance_profile` | A required wrapper that lets EC2 use an IAM role; you attach the profile name (not the role ARN) to an EC2 instance |
| `aws_iam_group_policy_attachment` | Attaches an existing policy (custom or managed) to a group; removing this resource detaches the policy |
| `aws_iam_role_policy_attachment` | Attaches an existing policy to a role; use the full ARN for AWS managed policies |
| `jsonencode` for policies | Converts a native Terraform HCL map into a JSON string; keeps policy documents readable without external `.json` files |
| Managed policy vs custom policy | AWS managed (`arn:aws:iam::aws:policy/...`) are pre-built and AWS-maintained; custom policies give you full least-privilege control |
| Principle of least privilege | Grant only the permissions an identity needs to do its job — nothing more; the foundation of secure IAM design |
