# Hands-On 3.4 --- Reusable Modules

**File:** `modules/web-server/`, `main.tf`, `variables.tf`, `outputs.tf`

---

## Concept

A **module** is a container for Terraform resources that are used together. Every Terraform configuration is already a module (the **root module**). When you call one module from another, the called module is a **child module**.

```
Root Module (your project)
├── main.tf            <-- calls child modules
├── variables.tf
├── outputs.tf
│
├── modules/
│   ├── web-server/    <-- child module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── database/      <-- another child module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
└── terraform.tfvars
```

### Why Modules?

| Without Modules | With Modules |
|----------------|-------------|
| Copy-paste resources across projects | Write once, reuse everywhere |
| 500-line `main.tf` files | Small, focused, testable units |
| Change in one place, forget others | Change module, all callers update |
| No encapsulation | Clear interface (inputs/outputs) |
| Hard to onboard new team members | Self-documenting via variables |

### Module Analogy

```
Module = Function

  module "web" {          function web(
    source = "./web"        instance_type,
    instance_type = "t3"    ami_id
    ami_id = "ami-123"    ) {
  }                         // create resources
                            return { ip, dns }
  output = module.web.ip  }
```

---

## 1. Module Inputs (Variables)

Child modules receive data through **input variables**, just like function parameters.

```hcl
# modules/web-server/variables.tf

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI ID for the web server"
  type        = string
  # No default = required input
}

variable "server_name" {
  description = "Name tag for the server"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to deploy into"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the instance"
  type        = string
}

variable "enable_monitoring" {
  description = "Enable detailed monitoring"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply"
  type        = map(string)
  default     = {}
}
```

---

## 2. Module Locals

Locals inside a module are **private** --- the caller cannot see or override them.

```hcl
# modules/web-server/locals.tf

locals {
  common_tags = merge(
    {
      Name      = var.server_name
      ManagedBy = "terraform"
      Module    = "web-server"
    },
    var.tags
  )

  sg_name = "${var.server_name}-sg"
}
```

---

## 3. Module Resources (main.tf)

```hcl
# modules/web-server/main.tf

resource "aws_security_group" "web" {
  name        = local.sg_name
  description = "Security group for ${var.server_name}"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_instance" "web" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.web.id]
  monitoring             = var.enable_monitoring

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Hello from ${var.server_name}</h1>" > /var/www/html/index.html
  EOF

  tags = local.common_tags
}
```

---

## 4. Module Outputs

Outputs are the module's **return values**. Only declared outputs are visible to the caller.

```hcl
# modules/web-server/outputs.tf

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.web.id
}

output "public_ip" {
  description = "Public IP address"
  value       = aws_instance.web.public_ip
}

output "private_ip" {
  description = "Private IP address"
  value       = aws_instance.web.private_ip
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.web.id
}
```

---

## 5. Calling the Module from Root

```hcl
# root main.tf

module "web_server" {
  source = "./modules/web-server"

  server_name  = "production-web"
  ami_id       = data.aws_ami.amazon_linux.id
  instance_type = "t3.small"
  vpc_id       = aws_vpc.main.id
  subnet_id    = aws_subnet.public[0].id

  enable_monitoring = true

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}

# Access module outputs
output "web_server_ip" {
  value = module.web_server.public_ip
}

output "web_server_id" {
  value = module.web_server.instance_id
}
```

```
module.web_server.public_ip
       ^              ^
       |              |
    module name    output name
```

---

## 6. File Paths in Modules

| Expression | Resolves to |
|-----------|------------|
| `path.module` | Directory of the current module |
| `path.root` | Directory of the root module |
| `path.cwd` | Current working directory |

```
project/
├── main.tf                  <-- path.root = here
└── modules/
    └── web-server/
        └── main.tf          <-- path.module = here
        └── templates/
            └── user_data.sh
```

```hcl
# Inside modules/web-server/main.tf

# CORRECT: use path.module to reference files within the module
user_data = templatefile("${path.module}/templates/user_data.sh", {
  server_name = var.server_name
})

# WRONG: path.root would look in the project root, not the module
# user_data = templatefile("${path.root}/templates/user_data.sh", {...})
```

> **Rule:** Always use `path.module` inside a module to reference the module's own files. Use `path.root` only when you intentionally need the root module's directory.

---

## 7. Module Gotchas

### 7.1 Count and For_Each with Modules

You can use `count` and `for_each` on module blocks:

```hcl
# Create 3 web servers using count
module "web_server" {
  source   = "./modules/web-server"
  count    = 3

  server_name = "web-${count.index}"
  ami_id      = data.aws_ami.amazon_linux.id
  vpc_id      = aws_vpc.main.id
  subnet_id   = aws_subnet.public[count.index % length(aws_subnet.public)].id
}

# Access: module.web_server[0].public_ip

# Create web servers using for_each
module "web_server_map" {
  source   = "./modules/web-server"
  for_each = toset(["frontend", "backend", "admin"])

  server_name = "${each.key}-server"
  ami_id      = data.aws_ami.amazon_linux.id
  vpc_id      = aws_vpc.main.id
  subnet_id   = aws_subnet.public[0].id
}

# Access: module.web_server_map["frontend"].public_ip
```

### 7.2 Provider Inheritance

Child modules **inherit** the default provider from the root module. You do not need to declare providers in child modules unless you need a different configuration.

```hcl
# Root module configures the provider
provider "aws" {
  region = "us-east-1"
}

# Child module automatically uses the above provider
module "web" {
  source = "./modules/web-server"
  # ...no provider block needed
}
```

To pass an **alternate** provider:

```hcl
provider "aws" {
  alias  = "west"
  region = "us-west-2"
}

module "web_west" {
  source = "./modules/web-server"
  providers = {
    aws = aws.west
  }
  # ...
}
```

### 7.3 Module Dependency

Modules automatically figure out dependencies from references. But you can force ordering:

```hcl
module "database" {
  source = "./modules/database"
  # ...
}

module "web_server" {
  source = "./modules/web-server"
  # ...

  # Explicit dependency (rarely needed)
  depends_on = [module.database]
}
```

---

## 8. Module Versioning

### 8.1 Local Modules

```hcl
module "web" {
  source = "./modules/web-server"   # Relative path
}
```

No versioning --- always uses current code on disk.

### 8.2 Git Repository

```hcl
module "web" {
  source = "git::https://github.com/acme/terraform-modules.git//web-server?ref=v1.2.0"
}

# SSH
module "web" {
  source = "git::ssh://git@github.com/acme/terraform-modules.git//web-server?ref=v1.2.0"
}
```

| URL Part | Meaning |
|----------|---------|
| `git::https://...` | Git protocol |
| `//web-server` | Subdirectory within the repo |
| `?ref=v1.2.0` | Git tag, branch, or commit SHA |

### 8.3 Terraform Registry

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name = "production-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
```

> **Tip:** Always pin module versions. Use `version = "5.5.1"` (exact) or `version = "~> 5.5"` (patch updates only). Never leave version unset for registry modules.

### Version Constraints

| Constraint | Meaning |
|-----------|---------|
| `= 1.0.0` | Exactly 1.0.0 |
| `>= 1.0.0` | 1.0.0 or newer |
| `~> 1.0` | >= 1.0, < 2.0 (minor updates) |
| `~> 1.0.0` | >= 1.0.0, < 1.1.0 (patch updates) |
| `>= 1.0, < 2.0` | Range |

---

## 9. Hands-On: Build a Complete Module

### Step 1: Create Project Structure

```bash
mkdir -p ~/module-lab/modules/web-server/templates
cd ~/module-lab
```

### Step 2: Create the Module

**modules/web-server/variables.tf:**
```hcl
variable "server_name" {
  description = "Name for the web server"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the instance"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
```

**modules/web-server/main.tf:**
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
}

locals {
  common_tags = {
    Name        = var.server_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group" "this" {
  name        = "${var.server_name}-sg"
  description = "SG for ${var.server_name}"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]

  user_data = templatefile("${path.module}/templates/user_data.sh", {
    server_name = var.server_name
  })

  tags = local.common_tags
}
```

**modules/web-server/templates/user_data.sh:**
```bash
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo "<h1>Hello from ${server_name}</h1>" > /var/www/html/index.html
```

**modules/web-server/outputs.tf:**
```hcl
output "instance_id" {
  description = "The EC2 instance ID"
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "The public IP of the instance"
  value       = aws_instance.this.public_ip
}

output "private_ip" {
  description = "The private IP of the instance"
  value       = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "The security group ID"
  value       = aws_security_group.this.id
}

output "ami_id" {
  description = "The AMI used for this instance"
  value       = data.aws_ami.amazon_linux.id
}
```

### Step 3: Create the Root Module

**providers.tf:**
```hcl
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
}
```

**main.tf:**
```hcl
# Look up default VPC and subnets
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Use our custom module
module "web" {
  source = "./modules/web-server"

  server_name   = "my-web-app"
  instance_type = "t3.micro"
  vpc_id        = data.aws_vpc.default.id
  subnet_id     = data.aws_subnets.default.ids[0]
  environment   = "dev"
}

# Use a registry module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name = "lab-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]

  enable_nat_gateway = false

  tags = {
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}
```

**outputs.tf:**
```hcl
# Outputs from our custom module
output "web_instance_id" {
  value = module.web.instance_id
}

output "web_public_ip" {
  value = module.web.public_ip
}

output "web_ami_id" {
  value = module.web.ami_id
}

# Outputs from the registry module
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnets
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}
```

### Step 4: Init and Plan

```bash
terraform init
```

Expected output:
```
Initializing modules...
- web in modules/web-server
Downloading registry.terraform.io/terraform-aws-modules/vpc/aws 5.5.1 for vpc...
- vpc in .terraform/modules/vpc

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.40.0...

Terraform has been successfully initialized!
```

```bash
terraform plan
```

Expected output (summary):
```
Plan: 18 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + web_instance_id    = (known after apply)
  + web_public_ip      = (known after apply)
  + vpc_id             = (known after apply)
  + public_subnet_ids  = (known after apply)
  + private_subnet_ids = (known after apply)
```

### Step 5: Inspect Module Resources

```bash
# Show planned resources from our module
terraform plan | grep "module.web"
```

```
  # module.web.aws_instance.this will be created
  # module.web.aws_security_group.this will be created
```

Notice how resources are namespaced: `module.web.aws_instance.this`

---

## 10. Module Best Practices

| Practice | Why |
|----------|-----|
| One purpose per module | Easy to understand and test |
| Expose only what callers need | Reduce coupling via outputs |
| Use `description` on all variables | Self-documenting |
| Set sensible defaults | Easier adoption |
| Validate inputs | Fail fast with clear errors |
| Use `path.module` for file references | Portable modules |
| Pin versions for registry modules | Reproducible builds |
| Name internal resources `this` | Convention when there is only one |
| Include a README.md | Help future users |
| Add `versions.tf` with constraints | Avoid surprises |

> **Key takeaway:** Modules are how Terraform scales from one person to a team. Think of them as reusable building blocks with a clear contract: variables go in, resources get created, outputs come out.
