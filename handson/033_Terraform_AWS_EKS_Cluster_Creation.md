# Lab 033 — Terraform AWS EKS Cluster Creation

**By: Saravanan Sundaramoorthy**
**Environment:** AWS ap-south-1 (Mumbai)
**Time to complete:** ~20 minutes (control plane ~7 min + node group ~3 min + setup ~10 min)

---

## Topic

| Concept | What it means |
|---------|--------------|
| **EKS** | Elastic Kubernetes Service — AWS fully manages the Kubernetes control plane (API server, etcd, scheduler, controller manager). You pay per hour for the control plane endpoint. |
| **Managed Node Group** | An Auto Scaling Group (ASG) that EKS manages on your behalf — it handles node provisioning, AMI updates, and draining. |
| **Cluster IAM Role** | Role assumed by the EKS control plane to call AWS APIs (describe EC2 subnets, create ENIs for pods, etc.). Requires `AmazonEKSClusterPolicy`. |
| **Node IAM Role** | Role assumed by the EC2 worker nodes (via instance profile). Requires three policies: `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`. |
| **Two separate IAM roles** | The cluster role and node role are always distinct — they serve different principals (`eks.amazonaws.com` vs `ec2.amazonaws.com`). |
| **`aws eks update-kubeconfig`** | Writes (or updates) the cluster's entry in `~/.kube/config` using IAM-based token authentication. `kubectl` uses this entry automatically. |
| **VPC / Subnets** | EKS needs at least two subnets (ideally in different AZs). This lab reuses the default VPC to keep the config minimal. |
| **Free-Tier instance type** | Training accounts may restrict non-free-tier instance types. This lab uses `t3.small` (free-tier eligible) instead of `t3.medium`. |

EKS separates the Kubernetes control plane (managed by AWS) from the data plane (your EC2 nodes). Terraform provisions the IAM roles, the cluster, and the managed node group. After `apply` you connect `kubectl` to the cluster with a single AWS CLI command and can immediately schedule workloads — which Lab 034 does via the Terraform Kubernetes provider.

---

## Architecture

```
                         ap-south-1
  ┌───────────────────────────────────────────────────────────────┐
  │                                                               │
  │   EKS Control Plane (AWS-managed)                             │
  │  ┌─────────────────────────────────────────────────────────┐  │
  │  │  aws_eks_cluster  "terraform-033-eks"   version 1.31    │  │
  │  │  IAM Role: eks_cluster_role                             │  │
  │  │    └── AmazonEKSClusterPolicy                           │  │
  │  └─────────────────────────────────────────────────────────┘  │
  │                        │                                      │
  │             Kubernetes API (HTTPS)                            │
  │                        │                                      │
  │   Managed Node Group                                          │
  │  ┌─────────────────────────────────────────────────────────┐  │
  │  │  aws_eks_node_group  "terraform-033-nodes"              │  │
  │  │  instance_type: t3.small   desired: 1  min: 1  max: 1   │  │
  │  │  IAM Role: eks_nodes_role                               │  │
  │  │    ├── AmazonEKSWorkerNodePolicy                        │  │
  │  │    ├── AmazonEKS_CNI_Policy                             │  │
  │  │    └── AmazonEC2ContainerRegistryReadOnly               │  │
  │  └─────────────────────────────────────────────────────────┘  │
  │                                                               │
  │   Networking (default VPC)                                    │
  │  ┌─────────────────────────────────────────────────────────┐  │
  │  │  data.aws_vpc.default  (default = true)                 │  │
  │  │  data.aws_subnets.default  (filtered by vpc-id)         │  │
  │  └─────────────────────────────────────────────────────────┘  │
  │                                                               │
  └───────────────────────────────────────────────────────────────┘

  Your laptop
    └── aws eks update-kubeconfig  →  ~/.kube/config  →  kubectl
```

---

## What Terraform Creates

| # | Resource | Name | Purpose |
|---|----------|------|---------|
| 1 | `aws_iam_role` | `eks-cluster-role` | Role for EKS control plane (principal: eks.amazonaws.com) |
| 2 | `aws_iam_role_policy_attachment` | cluster policy | Attaches `AmazonEKSClusterPolicy` to cluster role |
| 3 | `aws_iam_role` | `eks-nodes-role` | Role for EC2 worker nodes (principal: ec2.amazonaws.com) |
| 4 | `aws_iam_role_policy_attachment` | worker node policy | Attaches `AmazonEKSWorkerNodePolicy` to node role |
| 5 | `aws_iam_role_policy_attachment` | CNI policy | Attaches `AmazonEKS_CNI_Policy` to node role |
| 6 | `aws_iam_role_policy_attachment` | ECR read-only | Attaches `AmazonEC2ContainerRegistryReadOnly` to node role |
| 7 | `aws_eks_cluster` | `terraform-033-eks` | EKS control plane, version 1.31 |
| 8 | `aws_eks_node_group` | `terraform-033-nodes` | Managed node group: 1× t3.small |
| 9 | `kubernetes_namespace` | `robochef` | K8s namespace for app resources |
| 10 | `kubernetes_config_map` | `robochef-config` | App env vars injected into pods |
| 11 | `kubernetes_deployment` | `robochef-deployment` | 1× nginx:alpine pod with resource limits |
| 12 | `kubernetes_service` | `robochef-service` | ClusterIP service on port 80 |
| — | `data.aws_vpc.default` | — | Looks up the default VPC ID |
| — | `data.aws_subnets.default` | — | Lists all subnets in the default VPC |
| — | `data.aws_eks_cluster` | — | Reads cluster endpoint + CA cert for kubernetes provider |
| — | `data.aws_eks_cluster_auth` | — | Fetches short-lived IAM token for kubernetes provider |

---

## Important Note — Free-Tier Instance Types

During the live demo, using `t3.medium` produced the following error immediately after node-group creation began:

```
Error: error waiting for EKS Node Group (terraform-033-eks:terraform-033-nodes) to be
active: unexpected state 'CREATE_FAILED', NodegroupError:
  The specified instance type (t3.medium) is not eligible for Free Tier.
  Please use a Free Tier eligible instance type.
```

The training account is restricted to **free-tier eligible** instance types only. Switch to `t3.small`, which is free-tier eligible and sufficient for lab exercises.

To check which instance types are free-tier eligible on your account:

```bash
aws ec2 describe-instance-types \
  --filters Name=free-tier-eligible,Values=true \
  --query 'InstanceTypes[*].InstanceType' \
  --output table \
  --region ap-south-1
```

Typical output includes: `t2.micro`, `t3.micro`, `t3.small` — use any of these if `t3.medium` fails.

---

## Project Setup

```bash
mkdir -p ~/terraform-aws-eks-033-demo
cd ~/terraform-aws-eks-033-demo
```

---

## File: `providers.tf`

```hcl
terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}
```

> The `kubernetes` provider reads its endpoint, CA cert, and auth token directly from the EKS cluster data sources defined in `k8s.tf`. No static kubeconfig file is needed.

---

## File: `variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region to deploy the EKS cluster"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "Name for the EKS cluster"
  type        = string
  default     = "terraform-033-eks"
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group (must be free-tier eligible on restricted accounts)"
  type        = string
  default     = "t3.small"
}

variable "app_name" {
  description = "Application name — used as prefix for k8s Namespace, Deployment, Service, ConfigMap"
  type        = string
  default     = "robochef"
}

variable "replicas" {
  description = "Number of pod replicas in the Deployment"
  type        = number
  default     = 1
}
```

---

## File: `main.tf`

```hcl
# ─── Data sources — reuse the default VPC and its subnets ───────────────────

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ─── IAM Role for the EKS Control Plane ─────────────────────────────────────

resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ─── IAM Role for the EKS Worker Nodes (EC2) ─────────────────────────────────

resource "aws_iam_role" "eks_nodes" {
  name = "eks-nodes-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_read_only" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ─── EKS Cluster ─────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.31"

  vpc_config {
    subnet_ids = data.aws_subnets.default.ids
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]

  tags = {
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}

# ─── Managed Node Group ───────────────────────────────────────────────────────

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "terraform-033-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = data.aws_subnets.default.ids
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_read_only,
  ]

  tags = {
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}
```

---

## File: `outputs.tf`

```hcl
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "API server endpoint URL"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = aws_eks_cluster.this.version
}

output "kubeconfig_cmd" {
  description = "Run this command to configure kubectl access"
  value       = "aws eks update-kubeconfig --region ap-south-1 --name terraform-033-eks"
}
```

---

## File: `k8s.tf`

Kubernetes resources deployed onto the EKS cluster via the Terraform `kubernetes` provider.  
The two `data` blocks at the top supply the endpoint, CA cert, and auth token to the provider.

```hcl
# ── EKS auth data sources (used by the kubernetes provider in providers.tf) ───
data "aws_eks_cluster" "this" {
  name = aws_eks_cluster.this.name
}

data "aws_eks_cluster_auth" "this" {
  name = aws_eks_cluster.this.name
}

# ── 1. Namespace ───────────────────────────────────────────────────────────────
resource "kubernetes_namespace" "app" {
  metadata {
    name = var.app_name

    labels = {
      owner   = "saravanans"
      project = "robochef.co"
    }
  }
}

# ── 2. ConfigMap ───────────────────────────────────────────────────────────────
resource "kubernetes_config_map" "app" {
  metadata {
    name      = "${var.app_name}-config"
    namespace = kubernetes_namespace.app.metadata[0].name

    labels = {
      owner   = "saravanans"
      project = "robochef.co"
    }
  }

  data = {
    APP_ENV     = "production"
    APP_OWNER   = "saravanans"
    APP_PROJECT = "robochef.co"
    APP_PORT    = "80"
  }
}

# ── 3. Deployment ──────────────────────────────────────────────────────────────
resource "kubernetes_deployment" "app" {
  metadata {
    name      = "${var.app_name}-deployment"
    namespace = kubernetes_namespace.app.metadata[0].name

    labels = {
      owner   = "saravanans"
      project = "robochef.co"
    }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = var.app_name
      }
    }

    template {
      metadata {
        labels = {
          app     = var.app_name
          owner   = "saravanans"
          project = "robochef.co"
        }
      }

      spec {
        container {
          name  = var.app_name
          image = "nginx:alpine"

          port {
            container_port = 80
          }

          # Inject every key from the ConfigMap as an environment variable
          env_from {
            config_map_ref {
              name = kubernetes_config_map.app.metadata[0].name
            }
          }

          # Resource requests tell the scheduler the minimum headroom needed.
          # Limits cap how much the container can consume.
          # Both are important on small nodes like t3.small (2 vCPU, 2 GB RAM).
          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

# ── 4. Service ─────────────────────────────────────────────────────────────────
resource "kubernetes_service" "app" {
  metadata {
    name      = "${var.app_name}-service"
    namespace = kubernetes_namespace.app.metadata[0].name

    labels = {
      owner   = "saravanans"
      project = "robochef.co"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = var.app_name
    }

    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }
  }
}
```

### What `k8s.tf` creates

| # | Resource | Name | Purpose |
|---|----------|------|---------|
| 1 | `kubernetes_namespace` | `robochef` | Isolated namespace for all app resources |
| 2 | `kubernetes_config_map` | `robochef-config` | Env vars (APP_ENV, APP_OWNER, APP_PROJECT, APP_PORT) injected into pods |
| 3 | `kubernetes_deployment` | `robochef-deployment` | 1× nginx:alpine pod with ConfigMap env_from + resource limits |
| 4 | `kubernetes_service` | `robochef-service` | ClusterIP on port 80 pointing to the Deployment pods |

### Verify after apply

```bash
# Update kubeconfig first if not already done
aws eks update-kubeconfig --region ap-south-1 --name terraform-033-eks

# Check all resources in the namespace
kubectl get all -n robochef

# Verify ConfigMap env vars are injected
POD=$(kubectl get pods -n robochef -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD -n robochef -- env | grep APP
# APP_ENV=production
# APP_OWNER=saravanans
# APP_PROJECT=robochef.co
# APP_PORT=80

# Access nginx via port-forward
kubectl port-forward svc/robochef-service 8080:80 -n robochef &
curl http://localhost:8080
kill %1
```

---

## What Happens During Apply (Two-Phase Creation)

EKS cluster creation is not instant. The apply runs in two distinct phases:

### Phase 1 — Control Plane (~7 minutes)

Terraform creates the IAM roles immediately (a few seconds), then begins provisioning the EKS control plane (`aws_eks_cluster.this`). AWS spins up the API server, scheduler, controller manager, and etcd cluster entirely within AWS-managed infrastructure. During this time you will see:

```
aws_iam_role.eks_cluster: Creating...
aws_iam_role.eks_nodes: Creating...
aws_iam_role.eks_cluster: Creation complete after 1s
aws_iam_role.eks_nodes: Creation complete after 1s
aws_iam_role_policy_attachment.eks_cluster_policy: Creating...
aws_iam_role_policy_attachment.eks_worker_node_policy: Creating...
aws_iam_role_policy_attachment.eks_cni_policy: Creating...
aws_iam_role_policy_attachment.eks_ecr_read_only: Creating...
...all attachments complete...
aws_eks_cluster.this: Creating...
aws_eks_cluster.this: Still creating... [1m0s elapsed]
aws_eks_cluster.this: Still creating... [2m0s elapsed]
...
aws_eks_cluster.this: Still creating... [7m0s elapsed]
aws_eks_cluster.this: Creation complete after 7m12s
```

### Phase 2 — Node Group (~3 minutes)

Once the control plane is ready, Terraform creates the managed node group (`aws_eks_node_group.this`). EKS launches an Auto Scaling Group, provisions EC2 instances, installs the Kubernetes node components (kubelet, kube-proxy, aws-node CNI), and registers them with the cluster:

```
aws_eks_node_group.this: Creating...
aws_eks_node_group.this: Still creating... [1m0s elapsed]
aws_eks_node_group.this: Still creating... [2m0s elapsed]
aws_eks_node_group.this: Still creating... [3m0s elapsed]
aws_eks_node_group.this: Creation complete after 3m22s

Apply complete! Resources: 8 added, 0 changed, 0 destroyed.

Outputs:
cluster_endpoint  = "https://ABCDEF1234567890.gr7.ap-south-1.eks.amazonaws.com"
cluster_name      = "terraform-033-eks"
cluster_version   = "1.31"
kubeconfig_cmd    = "aws eks update-kubeconfig --region ap-south-1 --name terraform-033-eks"
```

Total wall-clock time: approximately **10 minutes**.

---

## Steps

### 1. Initialise

```bash
cd ~/terraform-aws-eks-033-demo
terraform init
```

Expected output:

```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Installing hashicorp/aws v6.x.x...

Terraform has been successfully initialized!
```

### 2. Validate

```bash
terraform validate
```

Expected output:

```
Success! The configuration is valid.
```

### 3. Plan

```bash
terraform plan
```

Review the plan. You should see **8 resources to add**:
- 2 `aws_iam_role` resources
- 4 `aws_iam_role_policy_attachment` resources
- 1 `aws_eks_cluster`
- 1 `aws_eks_node_group`

### 4. Apply

```bash
terraform apply
```

Type `yes` when prompted. The apply will take approximately 10 minutes. Monitor the progress messages as described in the "What Happens During Apply" section above.

---

## Post-Apply: Connect kubectl to the Cluster

After `terraform apply` completes, run the kubeconfig update command shown in the `kubeconfig_cmd` output:

```bash
aws eks update-kubeconfig --region ap-south-1 --name terraform-033-eks
```

Expected output:

```
Added new context arn:aws:eks:ap-south-1:123456789012:cluster/terraform-033-eks to /Users/saravanans/.kube/config
```

This command:
1. Calls the EKS API to retrieve the cluster's CA certificate and endpoint.
2. Writes a new context entry to `~/.kube/config`.
3. Configures `kubectl` to use the `aws eks get-token` authenticator (IAM-based token exchange).

---

## Verification

### Check Nodes

```bash
kubectl get nodes
```

Expected output:

```
NAME                              STATUS   ROLES    AGE     VERSION
ip-172-31-xx-xx.internal   Ready    <none>   2m38s   v1.31.14-eks-7fcd7ec
```

The single `t3.small` node should show `Ready`. The `ROLES` column shows `<none>` for worker nodes (control-plane nodes are AWS-managed and not visible here).

### Check System Pods

```bash
kubectl get pods -A
```

Expected output (all pods should be `Running`):

```
NAMESPACE     NAME                       READY   STATUS    RESTARTS   AGE
kube-system   aws-node-xxxxx             2/2     Running   0          3m
kube-system   coredns-xxxxxxxxxx-xxxxx   1/1     Running   0          8m
kube-system   coredns-xxxxxxxxxx-yyyyy   1/1     Running   0          8m
kube-system   kube-proxy-xxxxx           1/1     Running   0          3m
```

| Pod | Purpose |
|-----|---------|
| `aws-node` | AWS VPC CNI plugin — assigns pod IP addresses from the VPC subnet |
| `coredns` | DNS server for cluster-internal service discovery |
| `kube-proxy` | Maintains iptables/IPVS rules for Service IP routing |

### Check Cluster Info

```bash
kubectl cluster-info
```

Expected output:

```
Kubernetes control plane is running at https://ABCDEF1234567890.gr7.ap-south-1.eks.amazonaws.com
CoreDNS is running at https://ABCDEF1234567890.gr7.ap-south-1.eks.amazonaws.com/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

### Inspect Outputs

```bash
terraform output
```

Expected output:

```
cluster_endpoint  = "https://ABCDEF1234567890.gr7.ap-south-1.eks.amazonaws.com"
cluster_name      = "terraform-033-eks"
cluster_version   = "1.31"
kubeconfig_cmd    = "aws eks update-kubeconfig --region ap-south-1 --name terraform-033-eks"
```

---

## Key Concepts Explained

### 1. EKS = AWS-Managed Kubernetes Control Plane

With a self-managed Kubernetes cluster you provision and maintain the control-plane servers yourself (API server, etcd, controller manager, scheduler). EKS removes that burden: AWS runs the control plane in a multi-AZ, highly available configuration. You only manage worker nodes (or use Fargate to eliminate those too).

**Cost:** EKS charges approximately $0.10 per hour per cluster for the control plane, regardless of the number of nodes.

### 2. Two Separate IAM Roles Are Always Required

```
Principal: eks.amazonaws.com   →  aws_iam_role.eks_cluster
  Required policies:
    - AmazonEKSClusterPolicy   (lets EKS manage ENIs, security groups, etc.)

Principal: ec2.amazonaws.com   →  aws_iam_role.eks_nodes
  Required policies:
    - AmazonEKSWorkerNodePolicy          (allows nodes to call EKS APIs)
    - AmazonEKS_CNI_Policy               (allows aws-node to manage pod IPs)
    - AmazonEC2ContainerRegistryReadOnly (allows nodes to pull images from ECR)
```

A common mistake is to attach node policies to the cluster role or vice-versa. EKS will reject such configurations with a clear IAM error.

### 3. Node Group = Auto Scaling Group

`aws_eks_node_group` is a thin wrapper around an EC2 Auto Scaling Group. EKS manages the ASG lifecycle:
- Replaces unhealthy nodes automatically.
- Drains and terminates nodes safely during managed updates.
- In this lab `desired = min = max = 1` so the ASG never scales.

### 4. `aws eks update-kubeconfig` and IAM Auth

EKS uses AWS IAM for Kubernetes authentication. When `kubectl` makes an API call:
1. The `aws eks get-token` exec credential plugin generates a short-lived bearer token (valid 15 minutes) signed with your AWS identity.
2. The EKS API server validates the token against the `aws-auth` ConfigMap (or EKS access entries).
3. Your IAM user/role is mapped to a Kubernetes RBAC identity.

The `update-kubeconfig` command writes this exec plugin configuration into `~/.kube/config` so that all subsequent `kubectl` commands authenticate automatically.

### 5. This Cluster Is Used by Lab 034

Lab 034 deploys Kubernetes resources (Deployment, Service) onto this cluster using the Terraform `kubernetes` provider. **Do not destroy this cluster until after Lab 034 is complete.**

---

## Common Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `The specified instance type is not eligible for Free Tier` | Training account restricts non-free-tier instances | Change `node_instance_type` to `t3.small` or `t3.micro` |
| `Error: Kubernetes cluster unreachable` in Lab 034 | `~/.kube/config` not updated | Run `aws eks update-kubeconfig --region ap-south-1 --name terraform-033-eks` |
| `AccessDenied` when running `kubectl` | IAM user not in `aws-auth` ConfigMap | Use the same IAM identity that ran `terraform apply` |
| Node stuck in `NotReady` | CNI policy missing on node role | Verify `AmazonEKS_CNI_Policy` is attached to `eks-nodes-role` |
| `InvalidParameterException: roleArn` | Wrong role attached to cluster | Cluster role must trust `eks.amazonaws.com`, not `ec2.amazonaws.com` |

---

## Important — Do NOT Destroy Until After Lab 034

Lab 034 provisions Kubernetes resources (a Deployment and a Service) on this cluster using the Terraform Kubernetes provider. If you destroy the EKS cluster now, Lab 034 will have no cluster to connect to and will fail immediately.

**After Lab 034 is complete, come back and run the destroy steps below.**

---

## Cleanup (After Lab 034)

```bash
cd ~/terraform-aws-eks-033-demo
terraform destroy
```

Type `yes` when prompted.

Destroy time is approximately 10–12 minutes (node group is drained and terminated first, then the control plane is deleted).

After destroy completes, remove the provider cache:

```bash
rm -rf .terraform
```

Remove the cluster context from your kubeconfig to keep it clean:

```bash
kubectl config delete-context arn:aws:eks:ap-south-1:$(aws sts get-caller-identity --query Account --output text):cluster/terraform-033-eks
```

---

## Summary

| Step | Command | Time |
|------|---------|------|
| Init | `terraform init` | ~30 sec |
| Validate | `terraform validate` | instant |
| Plan | `terraform plan` | ~5 sec |
| Apply (control plane) | `terraform apply` | ~7 min |
| Apply (node group) | — | ~3 min |
| Connect kubectl | `aws eks update-kubeconfig ...` | instant |
| Verify nodes | `kubectl get nodes` | instant |
| Destroy (after Lab 034) | `terraform destroy && rm -rf .terraform` | ~10 min |

This lab creates a production-capable EKS cluster. Lab 034 uses this cluster to demonstrate how Terraform manages Kubernetes resources directly using the `kubernetes` provider — bridging infrastructure provisioning and application deployment in a single workflow.
