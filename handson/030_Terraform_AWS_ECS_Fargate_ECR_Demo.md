# 030 — Terraform AWS ECS Fargate + ECR Demo

**By: Saravanan Sundaramoorthy**
**Environment:** AWS ap-south-1 (Mumbai)
**Time to complete:** ~25 minutes

---

## Topic

| Concept | What it means |
|---------|--------------|
| **ECR** | Elastic Container Registry — AWS-managed Docker registry for storing container images |
| **ECS** | Elastic Container Service — AWS orchestration layer for running containers |
| **Fargate** | Serverless compute engine for ECS; no EC2 instances to manage |
| **Task Definition** | Blueprint for a container: image, CPU, memory, networking mode, log config |
| **ECS Service** | Keeps N running copies of a task definition; replaces failed tasks automatically |
| **`network_mode = awsvpc`** | Required for Fargate; each task gets its own ENI and private IP |
| **`target_type = ip`** | ALB target group must use `ip` for Fargate (not `instance`) |
| **`awslogs` log driver** | Streams container stdout/stderr to CloudWatch Logs |
| **`awslogs-create-group`** | Container-level option; tells the ECS agent to auto-create the log group |
| **`logs:CreateLogGroup`** | IAM action NOT covered by `AmazonECSTaskExecutionRolePolicy`; must be added manually |
| **ALB** | Application Load Balancer — distributes HTTP traffic to ECS tasks |

---

## Architecture

```
Internet
   |
   v
aws_lb  (terraform-030-alb, public, port 80)
   |
   v
aws_lb_listener  (HTTP:80)
   |
   v
aws_lb_target_group  (target_type = ip, port 80)
   |
   v
aws_ecs_service  (terraform-030-service, desired_count = 1)
   |
   v
aws_ecs_task_definition  (nginx:latest, 256 CPU / 512 MiB, FARGATE, LINUX/X86_64)
   |
   v
nginx container  →  HTTP 200  →  <title>Welcome to nginx!</title>

IAM:
  aws_iam_role  (terraform-030-ecs-task-exec-role)
    ├── aws_iam_role_policy_attachment  (AmazonECSTaskExecutionRolePolicy)
    └── aws_iam_role_policy  (logs:CreateLogGroup — inline fix)

Networking:
  aws_security_group  (alb-sg)   — allows inbound 80 from 0.0.0.0/0
  aws_security_group  (task-sg)  — allows inbound 80 from alb-sg only

ECR:
  aws_ecr_repository  (terraform-030-robochef-app)
    └── used for custom images; this lab runs nginx:latest from Docker Hub
```

---

## What Terraform Creates

| Resource | Description |
|----------|-------------|
| `aws_ecr_repository.app` | Private ECR repo for custom images (terraform-030-robochef-app) |
| `aws_iam_role.ecs_task_exec` | Execution role ECS assumes to pull images and write logs |
| `aws_iam_role_policy_attachment.ecs_exec` | Attaches `AmazonECSTaskExecutionRolePolicy` managed policy |
| `aws_iam_role_policy.logs_create_group` | Inline policy granting `logs:CreateLogGroup` (the fix) |
| `aws_security_group.alb_sg` | Allows inbound HTTP:80 from the internet to the ALB |
| `aws_security_group.task_sg` | Allows inbound HTTP:80 from the ALB SG only to ECS tasks |
| `aws_lb.alb` | Public-facing Application Load Balancer |
| `aws_lb_target_group.tg` | Target group with `target_type = ip` (required for Fargate) |
| `aws_lb_listener.http` | HTTP:80 listener; forwards traffic to the target group |
| `aws_ecs_cluster.cluster` | ECS cluster named terraform-030-cluster |
| `aws_ecs_task_definition.app` | Fargate task: nginx:latest, 256 CPU, 512 MiB, awsvpc, awslogs |
| `aws_ecs_service.service` | ECS service: 1 desired task, wired to ALB target group |
| **Total** | **12 resources** |

---

## Step 1 — Create the project folder

```bash
mkdir -p ~/terraform-aws-ecs-030-demo
cd ~/terraform-aws-ecs-030-demo
```

---

## Step 2 — Write all Terraform files

### `providers.tf`

```bash
cat > providers.tf <<'EOF_TF'
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Owner   = var.owner
      Project = var.project
    }
  }
}
EOF_TF
```

### `variables.tf`

```bash
cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "terraform-030"
}

variable "owner" {
  description = "Owner tag value"
  type        = string
  default     = "saravanans"
}

variable "project" {
  description = "Project tag value"
  type        = string
  default     = "robochef.co"
}

variable "vpc_id" {
  description = "VPC ID where resources will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
}

variable "task_subnet_ids" {
  description = "List of subnet IDs for ECS tasks (can be public or private)"
  type        = list(string)
}

variable "container_image" {
  description = "Docker image for the ECS task"
  type        = string
  default     = "nginx:latest"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 80
}

variable "task_cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Task memory in MiB"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of tasks to run"
  type        = number
  default     = 1
}
EOF_TF
```

### `terraform.tfvars`

> Replace the subnet and VPC IDs with values from your own AWS account.

```bash
cat > terraform.tfvars <<'EOF_TF'
vpc_id            = "vpc-xxxxxxxxxxxxxxxxx"
public_subnet_ids = ["subnet-xxxxxxxxxxxxxxxxx", "subnet-yyyyyyyyyyyyyyyyy"]
task_subnet_ids   = ["subnet-xxxxxxxxxxxxxxxxx", "subnet-yyyyyyyyyyyyyyyyy"]
EOF_TF
```

To find your default VPC and subnets:

```bash
# Get default VPC ID
aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" --output text

# Get subnets in the default VPC
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=<your-vpc-id>" \
  --query "Subnets[*].[SubnetId,AvailabilityZone]" \
  --output table
```

### `main.tf`

```bash
cat > main.tf <<'EOF_TF'
# --- ECR repository for custom images ---
resource "aws_ecr_repository" "app" {
  name                 = "${var.name_prefix}-robochef-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
}

# --- IAM: ECS task execution role ---
resource "aws_iam_role" "ecs_task_exec" {
  name = "${var.name_prefix}-ecs-task-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# --- IAM: attach managed ECS execution policy ---
resource "aws_iam_role_policy_attachment" "ecs_exec" {
  role       = aws_iam_role.ecs_task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- IAM: inline policy for logs:CreateLogGroup (not in the managed policy) ---
resource "aws_iam_role_policy" "logs_create_group" {
  name = "${var.name_prefix}-logs-create-group"
  role = aws_iam_role.ecs_task_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup"]
      Resource = "arn:aws:logs:*:*:log-group:/ecs/*"
    }]
  })
}

# --- Security group: ALB ---
resource "aws_security_group" "alb_sg" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Allow inbound HTTP from the internet to the ALB"
  vpc_id      = var.vpc_id

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
}

# --- Security group: ECS tasks ---
resource "aws_security_group" "task_sg" {
  name        = "${var.name_prefix}-task-sg"
  description = "Allow inbound HTTP from the ALB only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- ALB ---
resource "aws_lb" "alb" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids
}

# --- ALB target group: target_type = ip (required for Fargate) ---
resource "aws_lb_target_group" "tg" {
  name        = "${var.name_prefix}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }
}

# --- ALB listener ---
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# --- ECS cluster ---
resource "aws_ecs_cluster" "cluster" {
  name = "${var.name_prefix}-cluster"
}

# --- ECS task definition ---
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.name_prefix}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  execution_role_arn       = aws_iam_role.ecs_task_exec.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "app"
    image     = var.container_image
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.name_prefix}"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
        "awslogs-create-group"  = "true"
      }
    }
  }])
}

# --- ECS service ---
resource "aws_ecs_service" "service" {
  name            = "${var.name_prefix}-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.task_subnet_ids
    security_groups  = [aws_security_group.task_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http]
}
EOF_TF
```

**Key points about `main.tf`:**
- `target_type = "ip"` on the target group is mandatory for Fargate — tasks are identified by their private IP, not an EC2 instance ID
- `network_mode = "awsvpc"` gives each task its own ENI and is required for Fargate
- `awslogs-create-group = "true"` tells the ECS agent to create the CloudWatch log group if it doesn't exist
- `aws_iam_role_policy.logs_create_group` is the fix for the `ResourceNotFoundException` error when ECS tries to write logs (see Key Concept 3)
- `depends_on = [aws_lb_listener.http]` ensures ECS service is not registered until the ALB listener is ready

### `outputs.tf`

```bash
cat > outputs.tf <<'EOF_TF'
output "ecr_repository_url" {
  description = "ECR repository URL for pushing custom images"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.cluster.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.service.name
}

output "alb_dns_name" {
  description = "ALB public DNS — open this in a browser or use with curl"
  value       = "http://${aws_lb.alb.dns_name}"
}
EOF_TF
```

---

## Step 3 — Init, Fmt, Validate, Plan, Apply

```bash
terraform init
```

Expected output (key lines):
```
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Installing hashicorp/aws v6.x.x...

Terraform has been successfully initialized!
```

```bash
terraform fmt
terraform validate
# Success! The configuration is valid.

terraform plan
# Plan: 12 to add, 0 to change, 0 to destroy.
```

```bash
terraform apply -auto-approve
```

Expected output (key lines):
```
aws_ecr_repository.app: Creating...
aws_iam_role.ecs_task_exec: Creating...
aws_security_group.alb_sg: Creating...
aws_ecr_repository.app: Creation complete after 1s [id=terraform-030-robochef-app]
aws_iam_role.ecs_task_exec: Creation complete after 2s [id=terraform-030-ecs-task-exec-role]
aws_iam_role_policy_attachment.ecs_exec: Creating...
aws_iam_role_policy.logs_create_group: Creating...
aws_security_group.alb_sg: Creation complete after 2s [id=sg-xxxxxxxx]
aws_security_group.task_sg: Creating...
aws_lb.alb: Creating...
aws_iam_role_policy_attachment.ecs_exec: Creation complete after 1s
aws_iam_role_policy.logs_create_group: Creation complete after 1s
aws_security_group.task_sg: Creation complete after 2s [id=sg-yyyyyyyy]
aws_lb_target_group.tg: Creating...
aws_ecs_cluster.cluster: Creating...
aws_ecs_task_definition.app: Creating...
aws_lb_target_group.tg: Creation complete after 1s
aws_ecs_cluster.cluster: Creation complete after 1s [id=arn:aws:ecs:...]
aws_ecs_task_definition.app: Creation complete after 1s [id=terraform-030-task:1]
aws_lb.alb: Still creating... [30s elapsed]
aws_lb.alb: Creation complete after 2m30s [id=arn:aws:elasticloadbalancing:...]
aws_lb_listener.http: Creating...
aws_lb_listener.http: Creation complete after 1s
aws_ecs_service.service: Creating...
aws_ecs_service.service: Creation complete after 15s [id=arn:aws:ecs:...]

Apply complete! Resources: 12 added, 0 changed, 0 destroyed.

Outputs:

alb_dns_name       = "http://terraform-030-alb-277215966.ap-south-1.elb.amazonaws.com"
ecr_repository_url = "043000359118.dkr.ecr.ap-south-1.amazonaws.com/terraform-030-robochef-app"
ecs_cluster_name   = "terraform-030-cluster"
ecs_service_name   = "terraform-030-service"
```

> The ALB takes 2–3 minutes to provision. The ECS task takes an additional 30–60 seconds to start and pass its health check.

---

## Step 4 — Verify

### Wait for the task to be healthy

```bash
# Check the service status
aws ecs describe-services \
  --cluster terraform-030-cluster \
  --services terraform-030-service \
  --query "services[0].[status,runningCount,desiredCount]" \
  --output table
```

Expected:
```
-----------------------------
|     DescribeServices      |
+---------+---+-------------+
|  ACTIVE |  1  |  1        |
+---------+---+-------------+
```

### Curl the ALB

```bash
curl $(terraform output -raw alb_dns_name)
```

Expected response (nginx welcome page):
```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed...</p>
</body>
</html>
```

### Confirm HTTP 200

```bash
curl -s -o /dev/null -w "%{http_code}" $(terraform output -raw alb_dns_name)
# 200
```

### Confirm ECR repository exists

```bash
aws ecr describe-repositories \
  --query "repositories[?repositoryName=='terraform-030-robochef-app'].[repositoryName,repositoryUri]" \
  --output table
```

Expected:
```
-------------------------------------------------------------------------------------------
|                                   DescribeRepositories                                  |
+---------------------------+-------------------------------------------------------------+
|  terraform-030-robochef-app | 043000359118.dkr.ecr.ap-south-1.amazonaws.com/terraform-030-robochef-app |
+---------------------------+-------------------------------------------------------------+
```

---

## Key Concept 1 — `target_type = ip` is required for Fargate

When ECS runs a Fargate task, the task gets its own private IP address via `awsvpc` networking. There is no underlying EC2 instance to register with an ALB target group.

```hcl
resource "aws_lb_target_group" "tg" {
  target_type = "ip"   # REQUIRED for Fargate — do NOT use "instance"
  ...
}
```

| `target_type` | When to use | How ECS registers |
|---------------|-------------|-------------------|
| `instance` | EC2 launch type | Registers the EC2 instance ID |
| `ip` | Fargate (and EC2 awsvpc) | Registers the task's private IP |

If you set `target_type = "instance"` with Fargate, the ECS service will fail to register targets and your ALB will return HTTP 503.

---

## Key Concept 2 — `logs:CreateLogGroup` must be added separately

`AmazonECSTaskExecutionRolePolicy` grants these CloudWatch Logs permissions:

```
logs:CreateLogStream
logs:PutLogEvents
```

It does **not** grant `logs:CreateLogGroup`. When `awslogs-create-group = "true"` is set in the container's log configuration, the ECS agent tries to create the log group on first start. Without the extra permission, container startup fails with:

```
ResourceNotFoundException: The specified log group does not exist.
CannotStartContainerError: failed to initialize logging driver
```

**The fix — add an inline IAM policy:**

```hcl
resource "aws_iam_role_policy" "logs_create_group" {
  name = "${var.name_prefix}-logs-create-group"
  role = aws_iam_role.ecs_task_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup"]
      Resource = "arn:aws:logs:*:*:log-group:/ecs/*"
    }]
  })
}
```

You must also set the option in the task definition:

```hcl
logConfiguration = {
  logDriver = "awslogs"
  options = {
    "awslogs-create-group" = "true"   # tells the ECS agent to create the group
    ...
  }
}
```

Both pieces are required together. Missing either one causes the container to fail to start.

---

## Key Concept 3 — ECR push workflow for custom images

This lab runs `nginx:latest` from Docker Hub. For production workloads you push your own images to ECR. The workflow is:

```bash
# 1. Authenticate Docker to ECR
aws ecr get-login-password --region ap-south-1 \
  | docker login --username AWS --password-stdin \
    $(terraform output -raw ecr_repository_url | cut -d/ -f1)

# 2. Build your image
docker build -t my-app:latest ./app

# 3. Tag for ECR
docker tag my-app:latest $(terraform output -raw ecr_repository_url):latest

# 4. Push
docker push $(terraform output -raw ecr_repository_url):latest

# 5. Update the task definition to use your ECR image
# In variables.tf change:
#   container_image = "<account>.dkr.ecr.ap-south-1.amazonaws.com/terraform-030-robochef-app:latest"
# Then: terraform apply -auto-approve
```

| Step | Command | Notes |
|------|---------|-------|
| Auth | `aws ecr get-login-password \| docker login` | Token expires after 12 hours |
| Build | `docker build` | Runs locally or in CI |
| Tag | `docker tag` | Must match ECR URL exactly |
| Push | `docker push` | Layers are deduplicated |
| Deploy | `terraform apply` | Updates task definition revision |

---

## Step 5 — Destroy

```bash
terraform destroy -auto-approve
rm -rf .terraform
```

Expected:
```
Destroy complete! Resources: 12 destroyed.
```

> ECR repositories with images must be force-deleted. If you pushed custom images, empty the repository first:
> ```bash
> aws ecr delete-repository --repository-name terraform-030-robochef-app --force
> ```
> Then run `terraform destroy`.

---

## Concept Summary

| Concept | Key rule |
|---------|----------|
| ECR | Private Docker registry; authenticate with `aws ecr get-login-password` |
| ECS cluster | Logical grouping of tasks and services; no compute of its own with Fargate |
| Task definition | Immutable versioned blueprint; each `terraform apply` creates a new revision |
| Fargate | No EC2 to manage; you pay per task CPU/memory-second |
| `network_mode = awsvpc` | Required for Fargate; each task gets its own ENI |
| `target_type = ip` | Mandatory for Fargate ALB integration; uses task private IP |
| `awslogs-create-group` | Container option; ECS agent creates the CW log group automatically |
| `logs:CreateLogGroup` | Not in `AmazonECSTaskExecutionRolePolicy`; always add as inline policy |
| `AmazonECSTaskExecutionRolePolicy` | Covers ECR pull + CloudWatch log stream/put; not log group creation |
| ALB with ECS | `depends_on = [aws_lb_listener.http]` prevents race condition at service creation |
| ECR push workflow | Build → tag with ECR URI → `docker push` → update task definition |

---

## Copy-paste script (full flow)

```bash
mkdir -p ~/terraform-aws-ecs-030-demo
cd ~/terraform-aws-ecs-030-demo

cat > providers.tf <<'EOF_TF'
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Owner   = var.owner
      Project = var.project
    }
  }
}
EOF_TF

cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "terraform-030"
}

variable "owner" {
  description = "Owner tag value"
  type        = string
  default     = "saravanans"
}

variable "project" {
  description = "Project tag value"
  type        = string
  default     = "robochef.co"
}

variable "vpc_id" {
  description = "VPC ID where resources will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
}

variable "task_subnet_ids" {
  description = "List of subnet IDs for ECS tasks"
  type        = list(string)
}

variable "container_image" {
  description = "Docker image for the ECS task"
  type        = string
  default     = "nginx:latest"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 80
}

variable "task_cpu" {
  description = "Task CPU units"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Task memory in MiB"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of tasks to run"
  type        = number
  default     = 1
}
EOF_TF

# Edit terraform.tfvars with your actual VPC and subnet IDs before applying
cat > terraform.tfvars <<'EOF_TF'
vpc_id            = "vpc-xxxxxxxxxxxxxxxxx"
public_subnet_ids = ["subnet-xxxxxxxxxxxxxxxxx", "subnet-yyyyyyyyyyyyyyyyy"]
task_subnet_ids   = ["subnet-xxxxxxxxxxxxxxxxx", "subnet-yyyyyyyyyyyyyyyyy"]
EOF_TF

cat > main.tf <<'EOF_TF'
resource "aws_ecr_repository" "app" {
  name                 = "${var.name_prefix}-robochef-app"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = false }
}

resource "aws_iam_role" "ecs_task_exec" {
  name = "${var.name_prefix}-ecs-task-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec" {
  role       = aws_iam_role.ecs_task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "logs_create_group" {
  name = "${var.name_prefix}-logs-create-group"
  role = aws_iam_role.ecs_task_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup"]
      Resource = "arn:aws:logs:*:*:log-group:/ecs/*"
    }]
  })
}

resource "aws_security_group" "alb_sg" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Allow inbound HTTP from the internet to the ALB"
  vpc_id      = var.vpc_id
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
}

resource "aws_security_group" "task_sg" {
  name        = "${var.name_prefix}-task-sg"
  description = "Allow inbound HTTP from the ALB only"
  vpc_id      = var.vpc_id
  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "alb" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "tg" {
  name        = "${var.name_prefix}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

resource "aws_ecs_cluster" "cluster" {
  name = "${var.name_prefix}-cluster"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.name_prefix}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  execution_role_arn       = aws_iam_role.ecs_task_exec.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([{
    name      = "app"
    image     = var.container_image
    essential = true
    portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.name_prefix}"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
        "awslogs-create-group"  = "true"
      }
    }
  }])
}

resource "aws_ecs_service" "service" {
  name            = "${var.name_prefix}-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = var.task_subnet_ids
    security_groups  = [aws_security_group.task_sg.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "app"
    container_port   = var.container_port
  }
  depends_on = [aws_lb_listener.http]
}
EOF_TF

cat > outputs.tf <<'EOF_TF'
output "ecr_repository_url" {
  description = "ECR repository URL for pushing custom images"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.cluster.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.service.name
}

output "alb_dns_name" {
  description = "ALB public DNS"
  value       = "http://${aws_lb.alb.dns_name}"
}
EOF_TF

terraform init
terraform fmt
terraform validate
terraform plan
terraform apply -auto-approve

# Wait ~60s for the task to start, then verify
curl $(terraform output -raw alb_dns_name)
curl -s -o /dev/null -w "%{http_code}" $(terraform output -raw alb_dns_name)

# Cleanup
terraform destroy -auto-approve
rm -rf .terraform
```
