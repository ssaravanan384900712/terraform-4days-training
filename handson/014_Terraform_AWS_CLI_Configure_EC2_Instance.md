# 014 Terraform AWS CLI Configure EC2 Instance

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux 
**Time:** ~20 minutes
## Goal

In this demo, we will:

1. Install AWS CLI
2. Configure AWS CLI credentials
3. Create a Terraform project
4. Configure the AWS provider
5. Create a single EC2 instance using `resource "aws_instance"`
6. Verify the instance
7. Destroy the infrastructure safely

> This demo uses AWS, so it may create billable resources. Always run `terraform destroy` after practice.

---

## 1. Create Project Folder

```bash
mkdir -p ~/tf_aws_ec2
cd ~/tf_aws_ec2
```

---

## 2. Install AWS CLI

### Ubuntu / Linux

```bash
sudo apt update
sudo apt install -y unzip curl

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

aws --version
```

If AWS CLI is already installed and you want to update it:

```bash
sudo ./aws/install --update
aws --version
```

---

## 3. Configure AWS CLI

Run:

```bash
aws configure
```

Example input:

```text
AWS Access Key ID [None]: YOUR_ACCESS_KEY_ID
AWS Secret Access Key [None]: YOUR_SECRET_ACCESS_KEY
Default region name [None]: ap-south-1
Default output format [None]: json
```

Verify AWS CLI access:

```bash
aws sts get-caller-identity
```

Expected output:

```json
{
  "UserId": "AIDAxxxxxxxxxxxx",
  "Account": "123456789012",
  "Arn": "arn:aws:iam::123456789012:user/terraform-user"
}
```

---

## 4. Terraform File Structure

We will create these files:

```text
tf_aws_ec2/
├── providers.tf
├── variables.tf
├── main.tf
└── outputs.tf
```

---

## 5. Create `providers.tf`

```bash
cat > providers.tf <<'EOF_PROVIDER'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
EOF_PROVIDER
```

Check:

```bash
cat providers.tf
```

Output:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

---

## 6. Create `variables.tf`

```bash
cat > variables.tf <<'EOF_VARIABLES'
variable "aws_region" {
  description = "AWS region where EC2 instance will be created"
  type        = string
  default     = "ap-south-1"
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance"
  type        = string
  default     = "ami-0f5ee92e2d63afc18"

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "instance_name" {
  description = "Name tag for EC2 instance"
  type        = string
  default     = "terraform-demo-ec2"
}
EOF_VARIABLES
```

Check:

```bash
cat variables.tf
```

> Note: AMI IDs are region-specific. The default AMI above is an Ubuntu AMI commonly used for `ap-south-1`, but AMIs can change over time. If it fails, get a fresh AMI ID from the AWS Console → EC2 → AMIs.

---

## 7. Create `main.tf`

```bash
cat > main.tf <<'EOF_MAIN'
resource "aws_instance" "demo" {
  ami           = var.ami_id
  instance_type = var.instance_type

  tags = {
    Name        = var.instance_name
    Environment = "training"
    ManagedBy   = "terraform"
  }
}
EOF_MAIN
```

Check:

```bash
cat main.tf
```

Output:

```hcl
resource "aws_instance" "demo" {
  ami           = var.ami_id
  instance_type = var.instance_type

  tags = {
    Name        = var.instance_name
    Environment = "training"
    ManagedBy   = "terraform"
  }
}
```

---

## 8. Create `outputs.tf`

```bash
cat > outputs.tf <<'EOF_OUTPUTS'
output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.demo.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.demo.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.demo.private_ip
}
EOF_OUTPUTS
```

Check:

```bash
cat outputs.tf
```

---

## 9. Initialize Terraform

```bash
terraform init
```

Example output:

```text
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws...

Terraform has been successfully initialized!
```

---

## 10. Format and Validate

```bash
terraform fmt
terraform validate
```

Expected output:

```text
Success! The configuration is valid.
```

---

## 11. Preview Terraform Plan

```bash
terraform plan
```

Terraform will show that it wants to create one EC2 instance:

```text
Terraform will perform the following actions:

  # aws_instance.demo will be created
  + resource "aws_instance" "demo" {
      + ami           = "ami-0f5ee92e2d63afc18"
      + instance_type = "t3.micro"
      + tags          = {
          + "Environment" = "training"
          + "ManagedBy"   = "terraform"
          + "Name"        = "terraform-demo-ec2"
        }
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

---

## 12. Apply Terraform

```bash
terraform apply
```

Terraform asks for confirmation:

```text
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value:
```

Type:

```text
yes
```

Example output:

```text
aws_instance.demo: Creating...
aws_instance.demo: Still creating... [10s elapsed]
aws_instance.demo: Creation complete after 21s [id=i-0123456789abcdef0]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

instance_id = "i-0123456789abcdef0"
instance_private_ip = "172.31.10.20"
instance_public_ip = "13.233.xxx.xxx"
```

---

## 13. Verify EC2 Instance from AWS CLI

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=terraform-demo-ec2" \
  --query "Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,PublicIpAddress,PrivateIpAddress]" \
  --output table
```

Example output:

```text
-------------------------------------------------------------------
|                        DescribeInstances                        |
+----------------------+----------+----------+----------------+---+
|  i-0123456789abcdef0 | running  | t3.micro | 13.233.xxx.xxx |...|
+----------------------+----------+----------+----------------+---+
```

---

## 14. Check Terraform State

```bash
ls
```

Example:

```text
main.tf
outputs.tf
providers.tf
terraform.tfstate
terraform.tfstate.backup
variables.tf
```

Show resources managed by Terraform:

```bash
terraform state list
```

Output:

```text
aws_instance.demo
```

Show instance details from Terraform state:

```bash
terraform show
```

---

## 15. Read Output Values

```bash
terraform output
```

Specific output:

```bash
terraform output instance_id
terraform output instance_public_ip
```

---

## 16. Change Instance Name

Edit `variables.tf`:

```bash
nano variables.tf
```

Change:

```hcl
variable "instance_name" {
  description = "Name tag for EC2 instance"
  type        = string
  default     = "terraform-demo-ec2-updated"
}
```

Run:

```bash
terraform plan
terraform apply
```

Terraform will update the tag without recreating the instance.

---

## 17. Destroy the EC2 Instance

Very important after training:

```bash
terraform destroy
```

Type:

```text
yes
```

Example output:

```text
aws_instance.demo: Destroying... [id=i-0123456789abcdef0]
aws_instance.demo: Destruction complete after 30s

Destroy complete! Resources: 1 destroyed.
```

---

## 18. Complete One-Shot Copy-Paste Script

Use this to create the full Terraform demo quickly:

```bash
mkdir -p ~/tf_aws_ec2
cd ~/tf_aws_ec2

cat > providers.tf <<'EOF_PROVIDER'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
EOF_PROVIDER

cat > variables.tf <<'EOF_VARIABLES'
variable "aws_region" {
  description = "AWS region where EC2 instance will be created"
  type        = string
  default     = "ap-south-1"
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance"
  type        = string
  default     = "ami-0f5ee92e2d63afc18"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "instance_name" {
  description = "Name tag for EC2 instance"
  type        = string
  default     = "terraform-demo-ec2"
}
EOF_VARIABLES

cat > main.tf <<'EOF_MAIN'
resource "aws_instance" "demo" {
  ami           = var.ami_id
  instance_type = var.instance_type

  tags = {
    Name        = var.instance_name
    Environment = "training"
    ManagedBy   = "terraform"
  }
}
EOF_MAIN

cat > outputs.tf <<'EOF_OUTPUTS'
output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.demo.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.demo.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.demo.private_ip
}
EOF_OUTPUTS

terraform init
terraform fmt
terraform validate
terraform plan
```

Then run:

```bash
terraform apply
```

Type:

```text
yes
```

---

## 19. Key Learning Points

| Concept | Meaning |
|---|---|
| `provider "aws"` | Tells Terraform to use AWS |
| `var.aws_region` | Reads value from a variable |
| `resource "aws_instance" "demo"` | Creates one EC2 instance |
| `ami` | OS image used by EC2 |
| `instance_type` | Size/type of EC2 machine |
| `tags` | Labels attached to AWS resources |
| `terraform init` | Downloads provider plugins |
| `terraform plan` | Shows what Terraform will do |
| `terraform apply` | Creates or updates infrastructure |
| `terraform destroy` | Deletes infrastructure |

---

## 20. Common Errors

### Error: AWS credentials not found

```text
Error: No valid credential sources found
```

Fix:

```bash
aws configure
aws sts get-caller-identity
```

---

### Error: AMI ID does not exist

```text
InvalidAMIID.NotFound
```

Fix:

Use an AMI ID that exists in your selected region.

Example:

```bash
aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
  --query "Images | sort_by(@, &CreationDate)[-1].ImageId" \
  --output text
```

Then update `ami_id` in `variables.tf`.

---

### Error: Instance type not available

```text
Unsupported: The requested configuration is currently not supported
```

Fix:

Try another instance type:

```hcl
instance_type = "t3.micro"
```

---

### Error: Permission denied

```text
UnauthorizedOperation
```

Fix:

Your IAM user/role needs EC2 permissions such as:

```text
ec2:RunInstances
ec2:DescribeInstances
ec2:TerminateInstances
ec2:CreateTags
```

---

## 21. Cleanup Checklist

After practice, run:

```bash
terraform destroy
```

Then verify no demo EC2 is running:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=terraform-demo-ec2" \
  --query "Reservations[*].Instances[*].[InstanceId,State.Name]" \
  --output table
```

---

## References

- AWS CLI official install/update documentation: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- Terraform AWS provider `aws_instance` documentation: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance
