# Lab 1.2 - Terraform Setup and First Configuration

This lab walks you through setting up your environment for Terraform development. You will create an AWS IAM user, install Terraform on your operating system, configure the AWS provider, and write your very first Terraform configuration using the local provider. By the end of this lab, you will have a fully working Terraform environment ready for building AWS infrastructure.

---

## 1. AWS Account Setup

### 1.1 Create an IAM User for Terraform

Never use your AWS root account for day-to-day work. Create a dedicated IAM user for Terraform.

1. Log into the AWS Management Console as root or an admin user.

2. Navigate to **IAM > Users > Create user**.

3. Enter the following details:

   - **User name:** `terraform-lab-user`
   - **Access type:** Check "Provide user access to the AWS Management Console" (optional for labs)

4. Click **Next: Permissions**.

5. Select **Attach policies directly** and attach the following policy:

   - `AdministratorAccess` (for lab purposes only -- use least privilege in production)

6. Click **Next: Review > Create user**.

> **Warning:** `AdministratorAccess` grants full access to your AWS account. For production use, create a custom policy with only the permissions Terraform needs. For training labs, this simplifies the setup.

### 1.2 Create Access Keys

1. Go to **IAM > Users > terraform-lab-user > Security credentials**.

2. Under **Access keys**, click **Create access key**.

3. Select **Command Line Interface (CLI)**.

4. Check the acknowledgment box and click **Next > Create access key**.

5. **Save both values immediately** -- the Secret Access Key is shown only once:

   ```
   Access Key ID:     AKIAIOSFODNN7EXAMPLE
   Secret Access Key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
   ```

> **Tip:** Store these credentials securely. Never commit them to Git. Never share them. If compromised, delete and rotate immediately.

---

## 2. Installing Terraform

### 2.1 Install on Linux (Ubuntu/Debian)

```bash
# Add HashiCorp GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Add HashiCorp repository
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Update and install
sudo apt update && sudo apt install terraform -y

# Verify installation
terraform version
```

**Expected output:**
```
Terraform v1.9.x
on linux_amd64
```

### 2.2 Install on Linux (RHEL/CentOS/Amazon Linux)

```bash
# Add HashiCorp repository
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo

# Install Terraform
sudo yum install terraform -y

# Verify installation
terraform version
```

### 2.3 Install on macOS

```bash
# Using Homebrew
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Verify installation
terraform version
```

### 2.4 Install on Windows

```powershell
# Using Chocolatey
choco install terraform -y

# OR using Scoop
scoop install terraform

# Verify installation
terraform version
```

### 2.5 Manual Install (Any Platform)

```bash
# Download the binary for your OS from:
# https://developer.hashicorp.com/terraform/downloads

# Example for Linux amd64:
wget https://releases.hashicorp.com/terraform/1.9.5/terraform_1.9.5_linux_amd64.zip
unzip terraform_1.9.5_linux_amd64.zip
sudo mv terraform /usr/local/bin/
terraform version
```

---

## 3. Preparing Your Work Environment

### 3.1 Install AWS CLI

```bash
# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# macOS
brew install awscli

# Verify
aws --version
```

**Expected output:**
```
aws-cli/2.15.x Python/3.11.x Linux/6.x.x-xxx
```

### 3.2 Configure AWS CLI

```bash
aws configure
```

Enter the credentials from Step 1.2:

```
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]: us-east-1
Default output format [None]: json
```

Verify the configuration:

```bash
aws sts get-caller-identity
```

**Expected output:**
```json
{
    "UserId": "AIDAIOSFODNN7EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/terraform-lab-user"
}
```

### 3.3 VS Code Extensions (Recommended)

Install these VS Code extensions for the best Terraform editing experience:

| Extension | Publisher | Purpose |
|-----------|-----------|---------|
| **HashiCorp Terraform** | HashiCorp | Syntax highlighting, autocomplete, formatting |
| **Terraform Doc Snippets** | Run at Scale | Quick snippets for common resources |
| **AWS Toolkit** | Amazon Web Services | AWS resource browser, credential helper |

### 3.4 Directory Structure

Create your lab workspace:

```bash
mkdir -p ~/terraform-labs/lab-1.2-setup
cd ~/terraform-labs/lab-1.2-setup
```

A typical Terraform project structure looks like:

```
project/
  main.tf           # Primary resource definitions
  variables.tf      # Input variable declarations
  outputs.tf        # Output value declarations
  providers.tf      # Provider configuration
  terraform.tfvars  # Variable values (do not commit secrets)
  .gitignore        # Ignore .terraform/, *.tfstate, etc.
```

### 3.5 Create a .gitignore

```bash
cat > .gitignore << 'GITIGNORE'
# Terraform
.terraform/
*.tfstate
*.tfstate.backup
*.tfplan

# Credentials
*.tfvars
!example.tfvars

# OS
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/
GITIGNORE
```

---

## 4. Terraform Providers Overview

Providers are plugins that Terraform uses to interact with APIs. Each cloud service, SaaS platform, or other tool has its own provider.

### 4.1 The Terraform Registry

Browse providers at: **https://registry.terraform.io/browse/providers**

Popular providers include:

| Provider | Purpose | Maintainer |
|----------|---------|------------|
| `hashicorp/aws` | Amazon Web Services | HashiCorp |
| `hashicorp/azurerm` | Microsoft Azure | HashiCorp |
| `hashicorp/google` | Google Cloud Platform | HashiCorp |
| `hashicorp/kubernetes` | Kubernetes clusters | HashiCorp |
| `hashicorp/local` | Local file operations | HashiCorp |
| `hashicorp/random` | Random value generation | HashiCorp |
| `hashicorp/null` | Null resources / provisioners | HashiCorp |

### 4.2 Provider Versioning

Always pin your provider versions to avoid unexpected breaking changes:

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"    # Allows 5.x but not 6.x
    }
  }
}
```

**Version constraint syntax:**

| Constraint | Meaning |
|-----------|---------|
| `= 5.31.0` | Exactly this version |
| `>= 5.0` | This version or newer |
| `~> 5.0` | Any 5.x version (pessimistic) |
| `>= 5.0, < 6.0` | Range constraint |

### 4.3 Provider Block

The provider block configures a specific provider:

```hcl
provider "aws" {
  region = "us-east-1"
}
```

You can have multiple provider configurations using aliases:

```hcl
provider "aws" {
  region = "us-east-1"
  alias  = "east"
}

provider "aws" {
  region = "us-west-2"
  alias  = "west"
}

resource "aws_instance" "east_server" {
  provider      = aws.east
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
}

resource "aws_instance" "west_server" {
  provider      = aws.west
  ami           = "ami-0892d3c7ee96c0bf7"
  instance_type = "t2.micro"
}
```

---

## 5. Hands-On: First Terraform Configuration (Local Provider)

Before touching AWS, let us verify your setup with the simplest possible Terraform configuration -- creating a local file.

### Step 1: Create a working directory

```bash
mkdir -p ~/terraform-labs/lab-1.2-local
cd ~/terraform-labs/lab-1.2-local
```

### Step 2: Write the configuration

Create a file named `main.tf`:

```hcl
# main.tf - My first Terraform configuration

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

resource "local_file" "hello" {
  filename = "${path.module}/hello.txt"
  content  = "Hello, Terraform! This file was created by IaC.\n"
}

output "file_path" {
  value       = local_file.hello.filename
  description = "The path of the created file"
}
```

### Step 3: Initialize Terraform

```bash
terraform init
```

**Expected output:**
```
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/local versions matching "~> 2.0"...
- Installing hashicorp/local v2.5.1...
- Installed hashicorp/local v2.5.1 (signed by HashiCorp)

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!
```

### Step 4: Review the plan

```bash
terraform plan
```

**Expected output:**
```
Terraform used the selected providers to generate the following execution plan.

  # local_file.hello will be created
  + resource "local_file" "hello" {
      + content              = "Hello, Terraform! This file was created by IaC.\n"
      + content_base64sha256 = (known after apply)
      + content_base64sha512 = (known after apply)
      + content_md5          = (known after apply)
      + content_sha1         = (known after apply)
      + content_sha256       = (known after apply)
      + content_sha512       = (known after apply)
      + directory_permission = "0777"
      + file_permission      = "0777"
      + filename             = "./hello.txt"
      + id                   = (known after apply)
    }

Plan: 1 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + file_path = "./hello.txt"
```

### Step 5: Apply the configuration

```bash
terraform apply
```

Type `yes` when prompted. **Expected output:**
```
local_file.hello: Creating...
local_file.hello: Creation complete after 0s [id=a1b2c3d4e5f6...]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

file_path = "./hello.txt"
```

### Step 6: Verify the result

```bash
cat hello.txt
```

**Expected output:**
```
Hello, Terraform! This file was created by IaC.
```

### Step 7: Inspect the state

```bash
terraform state list
terraform state show local_file.hello
```

### Step 8: Destroy the resource

```bash
terraform destroy
```

Type `yes` when prompted. The `hello.txt` file is deleted.

> **Tip:** You have just completed the full Terraform lifecycle: write -> init -> plan -> apply -> destroy. This same workflow applies to every Terraform project, whether you are creating a local file or a 500-resource AWS environment.

---

## 6. AWS Provider Configuration Methods

The AWS provider supports multiple ways to supply credentials. Terraform evaluates them in this order of precedence:

### Method 1: Static Credentials in Provider Block (NOT recommended)

```hcl
provider "aws" {
  region     = "us-east-1"
  access_key = "AKIAIOSFODNN7EXAMPLE"
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
}
```

> **Warning:** NEVER hardcode credentials in your Terraform files. They will end up in version control and be exposed. This method exists only for documentation purposes.

### Method 2: Environment Variables (Good for CI/CD)

```bash
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_DEFAULT_REGION="us-east-1"
```

Then your provider block needs only:

```hcl
provider "aws" {
  region = "us-east-1"
}
```

### Method 3: Shared Credentials File (Recommended for local dev)

This is what `aws configure` sets up. Terraform reads from `~/.aws/credentials` automatically:

```ini
# ~/.aws/credentials
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

```ini
# ~/.aws/config
[default]
region = us-east-1
output = json
```

You can use named profiles:

```hcl
provider "aws" {
  region  = "us-east-1"
  profile = "terraform-lab"
}
```

### Method 4: IAM Instance Profile (Best for EC2-based workflows)

When running Terraform on an EC2 instance, attach an IAM Role to the instance. Terraform automatically discovers the credentials from the instance metadata service.

```hcl
provider "aws" {
  region = "us-east-1"
  # No credentials needed -- uses instance profile automatically
}
```

### Method 5: AWS SSO / IAM Identity Center

```bash
aws configure sso
# Follow the prompts to set up SSO

aws sso login --profile my-sso-profile
```

```hcl
provider "aws" {
  region  = "us-east-1"
  profile = "my-sso-profile"
}
```

### Credential Precedence Order

Terraform resolves AWS credentials in this order:

```
1. Static credentials in provider block
2. Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
3. Shared credentials file (~/.aws/credentials)
4. Shared configuration file (~/.aws/config)
5. Container credentials (ECS task role)
6. Instance profile credentials (EC2 IAM role)
```

---

## 7. Hands-On: First AWS Provider Configuration

### Step 1: Create a working directory

```bash
mkdir -p ~/terraform-labs/lab-1.2-aws
cd ~/terraform-labs/lab-1.2-aws
```

### Step 2: Write the provider configuration

Create `providers.tf`:

```hcl
# providers.tf

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = "lab"
      ManagedBy   = "terraform"
      Project     = "terraform-training"
    }
  }
}
```

> **Tip:** The `default_tags` block automatically applies these tags to every AWS resource Terraform creates. This is extremely useful for cost tracking and compliance.

### Step 3: Write a simple resource

Create `main.tf`:

```hcl
# main.tf

# Create an S3 bucket to verify AWS connectivity
resource "aws_s3_bucket" "test" {
  bucket = "my-terraform-lab-test-${random_id.suffix.hex}"

  tags = {
    Name = "Terraform Test Bucket"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

output "bucket_name" {
  value = aws_s3_bucket.test.bucket
}
```

Update `providers.tf` to add the random provider:

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = "lab"
      ManagedBy   = "terraform"
      Project     = "terraform-training"
    }
  }
}
```

### Step 4: Initialize and apply

```bash
terraform init
terraform plan
terraform apply
```

**Expected output (after typing `yes`):**
```
random_id.suffix: Creating...
random_id.suffix: Creation complete after 0s [id=abc123]
aws_s3_bucket.test: Creating...
aws_s3_bucket.test: Creation complete after 2s [id=my-terraform-lab-test-61626331]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

bucket_name = "my-terraform-lab-test-61626331"
```

### Step 5: Verify in AWS

```bash
aws s3 ls | grep terraform-lab-test
```

### Step 6: Clean up

```bash
terraform destroy
```

Type `yes` to confirm. The S3 bucket is deleted.

---

## 8. Understanding the .terraform Directory

After `terraform init`, explore what was created:

```bash
tree .terraform/
```

```
.terraform/
  providers/
    registry.terraform.io/
      hashicorp/
        aws/
          5.31.0/
            linux_amd64/
              terraform-provider-aws_v5.31.0_x5
        random/
          3.6.0/
            linux_amd64/
              terraform-provider-random_v3.6.0_x5
```

The `.terraform.lock.hcl` file records the exact provider versions and checksums used:

```hcl
# This file is maintained automatically by "terraform init".
provider "registry.terraform.io/hashicorp/aws" {
  version     = "5.31.0"
  constraints = "~> 5.0"
  hashes = [
    "h1:abc123...",
  ]
}
```

> **Tip:** Always commit `.terraform.lock.hcl` to version control. Never commit the `.terraform/` directory -- it contains large binary files.

---

## 9. Useful Terraform Commands

| Command | Purpose |
|---------|---------|
| `terraform init` | Initialize working directory |
| `terraform plan` | Preview changes |
| `terraform apply` | Apply changes |
| `terraform destroy` | Destroy all resources |
| `terraform fmt` | Format .tf files consistently |
| `terraform validate` | Validate configuration syntax |
| `terraform state list` | List resources in state |
| `terraform state show <resource>` | Show details of a resource |
| `terraform output` | Show output values |
| `terraform providers` | Show required providers |
| `terraform version` | Show Terraform version |

Try formatting your files right now:

```bash
terraform fmt
```

And validate them:

```bash
terraform validate
```

**Expected output:**
```
Success! The configuration is valid.
```

---

## Summary

| Task | Status |
|------|--------|
| AWS IAM user created | Done |
| Access keys generated and saved | Done |
| Terraform installed and verified | Done |
| AWS CLI configured | Done |
| Local provider hands-on complete | Done |
| AWS provider configured and tested | Done |
| First AWS resource created and destroyed | Done |

You now have a fully configured Terraform environment. In the next lab, you will deploy your first EC2 instance.
