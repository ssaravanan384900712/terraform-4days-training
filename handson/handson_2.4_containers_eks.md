# Lab 2.4 — Containers and EKS with Terraform

Amazon Elastic Kubernetes Service (EKS) is a managed Kubernetes control plane. In this lab you will build a complete EKS environment from scratch using Terraform: a dedicated VPC with public and private subnets, IAM roles for the cluster and node groups, the EKS cluster itself, managed node groups, an ECR repository for container images, and finally deploy a Kubernetes workload. This is a production-relevant exercise that covers the full lifecycle from network to running pods.

---

## Prerequisites

- Terraform >= 1.6 installed
- AWS CLI configured with permissions for EKS, EC2, IAM, and ECR
- `kubectl` installed (v1.28+)
- Approximate apply time: 15-20 minutes (EKS clusters take ~10 min to provision)

---

## Architecture Overview

```
VPC (10.0.0.0/16)
├── Public Subnet 1  (10.0.1.0/24) ── NAT Gateway ── Internet Gateway
├── Public Subnet 2  (10.0.2.0/24)
├── Private Subnet 1 (10.0.10.0/24) ── EKS Worker Nodes
├── Private Subnet 2 (10.0.20.0/24) ── EKS Worker Nodes
└── EKS Cluster (Control Plane)
    ├── Managed Node Group (2x t3.medium)
    └── CoreDNS, kube-proxy, vpc-cni add-ons

ECR Repository ── Container images
```

---

## Part 1 — Project Setup

### Step 1: Create the project structure

```bash
mkdir -p ~/lab2.4-eks && cd ~/lab2.4-eks
```

### Step 2: Create `variables.tf`

```hcl
# variables.tf

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "lab24-eks-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_instance_types" {
  description = "Instance types for the node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "dev"
}
```

### Step 3: Create `main.tf` with providers

```hcl
# main.tf

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Kubernetes provider configured after EKS is available
provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name]
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
```

---

## Part 2 — VPC and Networking

### Step 4: Create `vpc.tf`

```hcl
# vpc.tf

# --- VPC ---
resource "aws_vpc" "eks" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name                                        = "${var.cluster_name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}"  = "shared"
  }
}

# --- Internet Gateway ---
resource "aws_internet_gateway" "eks" {
  vpc_id = aws_vpc.eks.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# --- Public Subnets ---
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.eks.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.cluster_name}-public-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}"  = "shared"
    "kubernetes.io/role/elb"                     = "1"
  }
}

# --- Private Subnets ---
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.eks.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name                                        = "${var.cluster_name}-private-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}"  = "shared"
    "kubernetes.io/role/internal-elb"            = "1"
  }
}

# --- NAT Gateway (one per AZ for HA, using one for cost savings in lab) ---
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "eks" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.cluster_name}-nat"
  }

  depends_on = [aws_internet_gateway.eks]
}

# --- Route Tables ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.eks.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.eks.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks.id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt"
  }
}

# --- Route Table Associations ---
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

> **Note:** The `kubernetes.io/cluster/<name>` and `kubernetes.io/role/elb` tags are required for EKS to discover subnets when creating load balancers.

---

## Part 3 — IAM Roles for EKS

### Step 5: Create `iam.tf`

```hcl
# iam.tf

# --- EKS Cluster Role ---
resource "aws_iam_role" "eks_cluster" {
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

  tags = {
    Name = "${var.cluster_name}-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_service_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster.name
}

# --- EKS Node Group Role ---
resource "aws_iam_role" "eks_nodes" {
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

  tags = {
    Name = "${var.cluster_name}-node-role"
  }
}

# Attach required policies for worker nodes
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}
```

---

## Part 4 — EKS Cluster

### Step 6: Create `eks.tf`

```hcl
# eks.tf

# --- Security Group for EKS Cluster ---
resource "aws_security_group" "eks_cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.eks.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-cluster-sg"
  }
}

resource "aws_security_group_rule" "cluster_ingress_https" {
  description       = "Allow worker nodes to communicate with the cluster API"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.eks_cluster.id
}

# --- EKS Cluster ---
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = concat(
      aws_subnet.public[*].id,
      aws_subnet.private[*].id
    )
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # Enable control plane logging
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
  ]

  tags = {
    Name        = var.cluster_name
    Environment = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_service_policy,
  ]
}
```

> **Important:** The `depends_on` for IAM policy attachments is critical. Without it, Terraform might try to create the cluster before IAM policies are attached, causing an "AccessDeniedException".

---

## Part 5 — Managed Node Group

### Step 7: Create `node-group.tf`

```hcl
# node-group.tf

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = aws_iam_role.eks_nodes.arn

  # Deploy nodes in private subnets
  subnet_ids = aws_subnet.private[*].id

  instance_types = var.node_instance_types
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    environment = var.environment
    nodegroup   = "main"
  }

  tags = {
    Name        = "${var.cluster_name}-node-group"
    Environment = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_policy,
  ]
}
```

---

## Part 6 — EKS Add-ons

### Step 8: Create `addons.tf`

```hcl
# addons.tf

# Core networking add-on
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"

  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "vpc-cni"
  }
}

# DNS resolution within the cluster
resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.main]

  tags = {
    Name = "coredns"
  }
}

# Network proxy on each node
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"

  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "kube-proxy"
  }
}
```

> **Note:** CoreDNS requires at least one node to be running, hence the `depends_on` for the node group.

---

## Part 7 — Amazon ECR Repository

### Step 9: Create `ecr.tf`

```hcl
# ecr.tf

resource "aws_ecr_repository" "app" {
  name                 = "${var.cluster_name}/app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "${var.cluster_name}-app"
    Environment = var.environment
  }
}

# Lifecycle policy to keep only last 10 images
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app.repository_url
}
```

---

## Part 8 — Kubernetes Resources

### Step 10: Create `kubernetes.tf`

```hcl
# kubernetes.tf
# Deploy a sample application to the EKS cluster using the Kubernetes provider

resource "kubernetes_namespace" "app" {
  metadata {
    name = "lab24-app"
    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }

  depends_on = [aws_eks_node_group.main]
}

# --- Deployment ---
resource "kubernetes_deployment" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels = {
      app = "nginx"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "nginx"
      }
    }

    template {
      metadata {
        labels = {
          app = "nginx"
        }
      }

      spec {
        container {
          name  = "nginx"
          image = "nginx:1.25"

          port {
            container_port = 80
          }

          resources {
            limits = {
              cpu    = "250m"
              memory = "128Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }
        }
      }
    }
  }
}

# --- Service (NodePort) ---
resource "kubernetes_service" "nginx_nodeport" {
  metadata {
    name      = "nginx-nodeport"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    selector = {
      app = "nginx"
    }

    port {
      port        = 80
      target_port = 80
      node_port   = 30080
      protocol    = "TCP"
    }

    type = "NodePort"
  }
}

# --- Service (ClusterIP) ---
resource "kubernetes_service" "nginx_clusterip" {
  metadata {
    name      = "nginx-internal"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    selector = {
      app = "nginx"
    }

    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}
```

> **Service Types:**
> - **ClusterIP** (default): Internal-only, accessible within the cluster. Use for service-to-service communication.
> - **NodePort**: Exposes the service on each node's IP at a static port (30000-32767). Accessible from outside the cluster if nodes are reachable.
> - **LoadBalancer**: Provisions a cloud load balancer (e.g., AWS NLB/ALB). Best for production external traffic.

---

## Part 9 — Outputs and kubeconfig

### Step 11: Create `outputs.tf`

```hcl
# outputs.tf

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "EKS Kubernetes version"
  value       = aws_eks_cluster.main.version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.eks_cluster.id
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.eks.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (worker nodes)"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "node_group_status" {
  description = "Node group status"
  value       = aws_eks_node_group.main.status
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}
```

---

## Part 10 — Deploy and Verify

### Step 12: Initialize and apply

```bash
cd ~/lab2.4-eks

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Expected output (abbreviated):

```
aws_vpc.eks: Creating...
aws_vpc.eks: Creation complete after 3s [id=vpc-0abc123]
...
aws_eks_cluster.main: Creating...
aws_eks_cluster.main: Still creating... [5m0s elapsed]
aws_eks_cluster.main: Still creating... [10m0s elapsed]
aws_eks_cluster.main: Creation complete after 11m23s [id=lab24-eks-cluster]
...
aws_eks_node_group.main: Creating...
aws_eks_node_group.main: Still creating... [3m0s elapsed]
aws_eks_node_group.main: Creation complete after 4m12s
...
kubernetes_namespace.app: Creating...
kubernetes_deployment.nginx: Creating...
kubernetes_service.nginx_nodeport: Creating...
...

Apply complete! Resources: 28 added, 0 changed, 0 destroyed.
```

### Step 13: Configure kubectl and verify

```bash
# Configure kubectl (copy the command from terraform output)
aws eks update-kubeconfig --region us-east-1 --name lab24-eks-cluster

# Verify cluster connectivity
kubectl cluster-info

# Check nodes
kubectl get nodes
```

Expected output:

```
NAME                            STATUS   ROLES    AGE   VERSION
ip-10-0-10-45.ec2.internal     Ready    <none>   5m    v1.29.x
ip-10-0-20-123.ec2.internal    Ready    <none>   5m    v1.29.x
```

### Step 14: Verify Kubernetes resources

```bash
# Check pods
kubectl get pods -n lab24-app

# Expected:
# NAME                     READY   STATUS    RESTARTS   AGE
# nginx-7bf8c77b5b-abc12   1/1     Running   0          2m
# nginx-7bf8c77b5b-def34   1/1     Running   0          2m

# Check services
kubectl get svc -n lab24-app

# Expected:
# NAME             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
# nginx-internal   ClusterIP   172.20.45.123   <none>        80/TCP         2m
# nginx-nodeport   NodePort    172.20.67.89    <none>        80:30080/TCP   2m

# Describe the deployment
kubectl describe deployment nginx -n lab24-app
```

### Step 15: Push a container to ECR (optional exercise)

```bash
# Get ECR login
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  $(terraform output -raw ecr_repository_url | cut -d'/' -f1)

# Create a simple Dockerfile
cat > Dockerfile <<'EOF'
FROM nginx:1.25-alpine
COPY index.html /usr/share/nginx/html/
EOF

echo "<h1>Hello from EKS!</h1>" > index.html

# Build, tag, and push
ECR_URL=$(terraform output -raw ecr_repository_url)
docker build -t myapp:v1 .
docker tag myapp:v1 ${ECR_URL}:v1
docker push ${ECR_URL}:v1

# Verify the image was pushed and scanned
aws ecr describe-images --repository-name lab24-eks-cluster/app
```

---

## Kubernetes Resource Lifecycle Reference

| Resource    | Purpose                                    | Key Fields                           |
|-------------|--------------------------------------------|--------------------------------------|
| Pod         | Smallest deployable unit (1+ containers)   | containers, volumes, restartPolicy   |
| Deployment  | Manages ReplicaSets, rolling updates       | replicas, strategy, template         |
| Service     | Stable network endpoint for pods           | selector, ports, type                |
| Namespace   | Logical isolation boundary                 | name, labels                         |
| ConfigMap   | Non-sensitive configuration data           | data (key-value pairs)               |
| Secret      | Sensitive data (base64 encoded)            | data, type                           |

---

## Clean Up

```bash
# Destroy all resources (takes ~10-15 minutes)
terraform destroy -auto-approve

# Verify cluster is gone
aws eks describe-cluster --name lab24-eks-cluster 2>&1 | grep "not found"
```

> **Warning:** EKS clusters cost approximately $0.10/hour for the control plane plus EC2 instance costs for nodes. Always destroy lab resources when finished.

---

## Summary

In this lab you built a complete EKS environment from the ground up:

| Component          | What You Created                                          |
|--------------------|-----------------------------------------------------------|
| Networking         | VPC, subnets, NAT gateway, route tables with EKS tags    |
| IAM                | Cluster role and node role with required AWS policies     |
| EKS Cluster        | Managed control plane with logging enabled                |
| Node Group         | Managed worker nodes in private subnets                   |
| Add-ons            | vpc-cni, coredns, kube-proxy                              |
| ECR                | Container registry with lifecycle policy and scanning     |
| Kubernetes         | Namespace, Deployment, NodePort and ClusterIP Services    |

> **Key takeaway:** Terraform can manage the full lifecycle from cloud infrastructure (VPC, IAM) through to Kubernetes resources (Deployments, Services) in a single configuration. The `kubernetes` provider authenticates to EKS using the cluster endpoint from the `aws_eks_cluster` resource, creating a seamless infrastructure-as-code pipeline.
