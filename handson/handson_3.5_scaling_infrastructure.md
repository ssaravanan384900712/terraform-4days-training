# Hands-On 3.5 --- Scaling Infrastructure

**File:** `main.tf`, `variables.tf`, `outputs.tf`, `asg.tf`, `alb.tf`

---

## Concept

Scaling infrastructure means going from one server to many --- reliably, automatically, and without downtime. Terraform handles this through counting mechanisms (`count`, `for_each`), Auto Scaling Groups, and Load Balancers.

```
                       Internet
                          |
                    +-----+-----+
                    |    ALB    |
                    | (Layer 7) |
                    +-----+-----+
                     /    |    \
                    /     |     \
            +------+ +------+ +------+
            | EC2  | | EC2  | | EC2  |
            | AZ-a | | AZ-b | | AZ-c |
            +------+ +------+ +------+
                 \       |       /
                  Auto Scaling Group
                  min=2, max=6, desired=3
```

### Scaling Approaches

| Approach | How | When |
|----------|-----|------|
| `count` | Fixed number of identical resources | Known fleet size |
| `for_each` | Map/set of named resources | Heterogeneous fleet |
| Auto Scaling Group | AWS manages fleet size | Dynamic load |
| Load Balancer | Distribute traffic | High availability |
| Immutable deploys | Replace, never patch | Zero-downtime updates |

---

## 1. Counting Servers with `count`

```hcl
variable "server_count" {
  description = "Number of web servers"
  type        = number
  default     = 3
}

resource "aws_instance" "web" {
  count         = var.server_count
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  subnet_id     = element(aws_subnet.public[*].id, count.index)

  tags = {
    Name = "web-server-${count.index}"
  }
}

output "instance_ips" {
  value = aws_instance.web[*].public_ip
}
```

```
Result:
  web-server-0  in subnet-a  10.0.1.10
  web-server-1  in subnet-b  10.0.2.10
  web-server-2  in subnet-a  10.0.1.11  (wraps with element())
```

> **Gotcha:** With `count`, removing server 0 causes servers 1 and 2 to shift down, recreating them. Use `for_each` when resources have distinct identities.

---

## 2. Named Servers with `for_each`

```hcl
variable "servers" {
  description = "Map of server configurations"
  type = map(object({
    instance_type = string
    subnet_index  = number
  }))
  default = {
    frontend = { instance_type = "t3.small", subnet_index = 0 }
    backend  = { instance_type = "t3.medium", subnet_index = 1 }
    worker   = { instance_type = "t3.large", subnet_index = 1 }
  }
}

resource "aws_instance" "app" {
  for_each      = var.servers
  ami           = data.aws_ami.amazon_linux.id
  instance_type = each.value.instance_type
  subnet_id     = aws_subnet.private[each.value.subnet_index].id

  tags = {
    Name = "${each.key}-server"
    Role = each.key
  }
}

output "server_ips" {
  value = { for k, v in aws_instance.app : k => v.private_ip }
}
```

```
Result:
  aws_instance.app["frontend"]  t3.small   10.0.1.20
  aws_instance.app["backend"]   t3.medium  10.0.2.20
  aws_instance.app["worker"]    t3.large   10.0.2.21
```

Removing "worker" from the map only destroys that one server --- no shifting.

---

## 3. High Availability with Multi-AZ

### VPC Foundation

```hcl
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "scaling-lab-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "scaling-lab-igw" }
}

resource "aws_subnet" "public" {
  count                   = length(local.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "public-${local.azs[count.index]}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
```

---

## 4. Auto Scaling Group (ASG)

An ASG automatically maintains a fleet of EC2 instances, replacing unhealthy ones and scaling based on demand.

```
                  ASG Configuration
                  ┌──────────────┐
                  │ min_size = 2 │
                  │ max_size = 6 │
                  │ desired  = 3 │
                  └──────┬───────┘
                         │
          ┌──────────────┼──────────────┐
          │              │              │
     +----+----+   +----+----+   +----+----+
     |  AZ-a   |   |  AZ-b   |   |  AZ-c   |
     | i-abc01 |   | i-abc02 |   | i-abc03 |
     +---------+   +---------+   +---------+
```

### Launch Template

```hcl
resource "aws_launch_template" "web" {
  name_prefix   = "web-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    echo "<h1>Hello from $INSTANCE_ID</h1>" > /var/www/html/index.html
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name      = "web-asg-instance"
      ManagedBy = "terraform"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}
```

### Auto Scaling Group

```hcl
resource "aws_autoscaling_group" "web" {
  name                = "web-asg"
  desired_capacity    = 3
  min_size            = 2
  max_size            = 6
  vpc_zone_identifier = aws_subnet.public[*].id
  health_check_type   = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  # Attach to ALB target group
  target_group_arns = [aws_lb_target_group.web.arn]

  # Rolling update configuration
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 60
    }
  }

  tag {
    key                 = "Name"
    value               = "web-asg-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "production"
    propagate_at_launch = true
  }
}
```

---

## 5. Application Load Balancer (ALB)

```
Client Request (HTTPS)
       |
       v
  +----+----+
  |   ALB   |  <-- Listener on port 80
  +---------+
       |
       v
  +----+------+
  | Target    |  <-- Health checks on /
  | Group     |
  +----+------+
    /     \
   v       v
 EC2-a   EC2-b    <-- Healthy targets
```

### Security Groups

```hcl
resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "alb-sg" }
}

resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "Security group for web servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "web-sg" }
}
```

### ALB, Target Group, and Listener

```hcl
resource "aws_lb" "web" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = { Name = "web-alb" }
}

resource "aws_lb_target_group" "web" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 10
    matcher             = "200"
  }

  tags = { Name = "web-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
```

---

## 6. Immutable Infrastructure

### The Philosophy

```
Mutable (Traditional)         Immutable (Modern)
┌─────────────┐               ┌─────────────┐
│ Server v1   │               │ Server v1   │──> terminate
│ yum update  │               └─────────────┘
│ deploy v2   │               ┌─────────────┐
│ config edit │               │ Server v2   │──> new AMI, new instance
└─────────────┘               └─────────────┘
  Drift risk: HIGH              Drift risk: NONE
```

| Aspect | Mutable | Immutable |
|--------|---------|-----------|
| Updates | SSH in, modify | Build new AMI, replace |
| Drift | Accumulates over time | Impossible by design |
| Rollback | Undo changes (risky) | Launch old AMI (safe) |
| Debugging | "What changed?" | "Which AMI version?" |

### Packer AMI Baking (Conceptual)

```
Source Code --> Packer Build --> AMI --> Terraform Deploy

packer/
  web-server.pkr.hcl:
    source "amazon-ebs" "web" {
      ami_name      = "web-server-{{timestamp}}"
      instance_type = "t3.micro"
      source_ami    = "ami-0c55b159..."
    }
    build {
      provisioner "shell" {
        inline = [
          "sudo yum install -y httpd",
          "sudo systemctl enable httpd"
        ]
      }
    }

$ packer build web-server.pkr.hcl
==> Builds finished. AMI: ami-0newbaked123
```

Then in Terraform:
```hcl
data "aws_ami" "web" {
  most_recent = true
  owners      = ["self"]
  filter {
    name   = "name"
    values = ["web-server-*"]
  }
}

# ASG launch template uses the latest baked AMI
resource "aws_launch_template" "web" {
  image_id = data.aws_ami.web.id
  # ...
}
```

---

## 7. Rolling AMI Upgrades with Instance Refresh

When you update the launch template (new AMI), the ASG's `instance_refresh` block handles the rolling update:

```
Time 0:  [v1] [v1] [v1]         3 instances running v1
Time 1:  [v1] [v1] [v1] [v2]   New v2 launched
Time 2:  [v1] [v1] [--] [v2]   One v1 terminated
Time 3:  [v1] [v1] [v2] [v2]   Health check passes
Time 4:  [v1] [--] [v2] [v2]   Another v1 terminated
Time 5:  [v1] [v2] [v2] [v2]   Continue...
Time 6:  [--] [v2] [v2] [v2]   Last v1 terminated
Time 7:  [v2] [v2] [v2]         All running v2
```

The `instance_refresh` block in the ASG config:

```hcl
instance_refresh {
  strategy = "Rolling"
  preferences {
    min_healthy_percentage = 50    # At least 50% healthy at all times
    instance_warmup        = 60    # Seconds to wait before checking health
  }
  triggers = ["launch_template"]   # Refresh when template changes
}
```

To trigger a rolling update:
```bash
# Update the AMI in the launch template, then apply
terraform apply
```

---

## 8. Blue-Green Deployment Pattern

Two identical environments, only one serves live traffic at a time:

```
                   DNS / ALB Listener Rule
                          |
               +----------+----------+
               |                     |
        +------+------+      +------+------+
        | BLUE (live) |      | GREEN (idle)|
        | ASG + TG    |      | ASG + TG    |
        | v1.0        |      | v2.0        |
        +-------------+      +-------------+

Step 1: Deploy v2.0 to GREEN
Step 2: Test GREEN
Step 3: Switch listener to GREEN
Step 4: GREEN is now live, BLUE is idle
Step 5: Destroy BLUE (or keep for rollback)
```

### Implementation

```hcl
variable "active_color" {
  description = "Which environment is live: blue or green"
  type        = string
  default     = "blue"
}

# Blue environment
resource "aws_lb_target_group" "blue" {
  name     = "web-blue-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path = "/"
  }
}

resource "aws_autoscaling_group" "blue" {
  name                = "web-blue-asg"
  desired_capacity    = var.active_color == "blue" ? 3 : 0
  min_size            = var.active_color == "blue" ? 2 : 0
  max_size            = 6
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = [aws_lb_target_group.blue.arn]

  launch_template {
    id      = aws_launch_template.blue.id
    version = "$Latest"
  }
}

# Green environment
resource "aws_lb_target_group" "green" {
  name     = "web-green-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path = "/"
  }
}

resource "aws_autoscaling_group" "green" {
  name                = "web-green-asg"
  desired_capacity    = var.active_color == "green" ? 3 : 0
  min_size            = var.active_color == "green" ? 2 : 0
  max_size            = 6
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = [aws_lb_target_group.green.arn]

  launch_template {
    id      = aws_launch_template.green.id
    version = "$Latest"
  }
}

# ALB listener points to the active color
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = (
      var.active_color == "blue"
        ? aws_lb_target_group.blue.arn
        : aws_lb_target_group.green.arn
    )
  }
}
```

Switch traffic:
```bash
# Deploy to green, then switch
terraform apply -var="active_color=green"
```

---

## 9. Full Hands-On: VPC + ASG + ALB

### Complete Project

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

**variables.tf:**
```hcl
variable "project_name" {
  default = "scaling-lab"
}

variable "desired_capacity" {
  default = 2
}

variable "max_size" {
  default = 4
}

variable "min_size" {
  default = 1
}
```

**main.tf (full stack):**
```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

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
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# --- VPC ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "public" {
  count                   = length(local.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet("10.0.0.0/16", 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-public-${local.azs[count.index]}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- Security Groups ---
resource "aws_security_group" "alb" {
  name   = "${var.project_name}-alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-alb-sg" }
}

resource "aws_security_group" "web" {
  name   = "${var.project_name}-web-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-web-sg" }
}

# --- ALB ---
resource "aws_lb" "web" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  tags = { Name = "${var.project_name}-alb" }
}

resource "aws_lb_target_group" "web" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 10
    matcher             = "200"
  }
  tags = { Name = "${var.project_name}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# --- ASG ---
resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/instance-id)
    AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/placement/availability-zone)
    cat > /var/www/html/index.html <<HTML
    <h1>Scaling Lab</h1>
    <p>Instance: $INSTANCE_ID</p>
    <p>AZ: $AZ</p>
    HTML
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-instance"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web" {
  name                      = "${var.project_name}-asg"
  desired_capacity          = var.desired_capacity
  min_size                  = var.min_size
  max_size                  = var.max_size
  vpc_zone_identifier       = aws_subnet.public[*].id
  health_check_type         = "ELB"
  health_check_grace_period = 300
  target_group_arns         = [aws_lb_target_group.web.arn]

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 60
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-instance"
    propagate_at_launch = true
  }
}
```

**outputs.tf:**
```hcl
output "alb_dns_name" {
  description = "DNS name of the ALB - open in browser"
  value       = "http://${aws_lb.web.dns_name}"
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "asg_name" {
  value = aws_autoscaling_group.web.name
}
```

### Deploy and Test

```bash
terraform init
terraform apply -auto-approve
```

Expected output:
```
Apply complete! Resources: 13 added, 0 changed, 0 destroyed.

Outputs:

alb_dns_name = "http://scaling-lab-alb-123456.us-east-1.elb.amazonaws.com"
asg_name     = "scaling-lab-asg"
vpc_id       = "vpc-0abc123"
```

Test the ALB:
```bash
# Wait 2-3 minutes for instances to become healthy, then:
curl http://scaling-lab-alb-123456.us-east-1.elb.amazonaws.com

# Hit it multiple times to see different instance IDs (load balancing)
for i in {1..5}; do
  curl -s http://scaling-lab-alb-123456.us-east-1.elb.amazonaws.com | grep Instance
done
```

Expected output (different IDs = load balancing works):
```
<p>Instance: i-0abc123def456</p>
<p>Instance: i-0def789abc012</p>
<p>Instance: i-0abc123def456</p>
<p>Instance: i-0def789abc012</p>
<p>Instance: i-0abc123def456</p>
```

### Trigger a Rolling Update

```bash
# Scale up
terraform apply -var="desired_capacity=4" -var="max_size=6" -auto-approve

# Check ASG status
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names scaling-lab-asg \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:Instances[*].InstanceId}' \
  --output table
```

### Clean Up

```bash
terraform destroy -auto-approve
```

---

## 10. Summary

| Component | Resource | Purpose |
|-----------|----------|---------|
| VPC | `aws_vpc` | Network isolation |
| Subnets | `aws_subnet` | Multi-AZ placement |
| ALB | `aws_lb` | Traffic distribution |
| Target Group | `aws_lb_target_group` | Health checking |
| Listener | `aws_lb_listener` | Port/protocol routing |
| Launch Template | `aws_launch_template` | Instance blueprint |
| ASG | `aws_autoscaling_group` | Fleet management |
| Instance Refresh | `instance_refresh` block | Zero-downtime updates |

> **Key takeaway:** Production infrastructure requires redundancy (multi-AZ), elasticity (ASG), and distribution (ALB). Terraform manages all of these as code, enabling repeatable, reviewable scaling changes.
