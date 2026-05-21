# Lab 034 — Terraform Kubernetes Resources via Kubernetes Provider

**By: Saravanan Sundaramoorthy**
**Environment:** AWS ap-south-1 (Mumbai) — EKS cluster from Lab 033
**Time to complete:** ~15 minutes

---

## Topic

| Concept | What it means |
|---------|--------------|
| **`kubernetes` provider** | HashiCorp-maintained provider that manages Kubernetes resources the same way Terraform manages AWS resources |
| **`data "aws_eks_cluster"`** | Reads the EKS cluster endpoint and CA certificate from the existing Lab 033 cluster |
| **`data "aws_eks_cluster_auth"`** | Calls the AWS IAM token endpoint to get a short-lived bearer token for the Kubernetes API |
| **`kubernetes_namespace`** | Creates a Kubernetes namespace to isolate the app's resources |
| **`kubernetes_config_map`** | Stores non-sensitive configuration key-value pairs; injected into pods as environment variables |
| **`kubernetes_deployment`** | Declarative desired state for replica pods — Terraform can diff and reconcile on every apply |
| **`kubernetes_service`** | Stable ClusterIP endpoint that load-balances across matching pods |
| **`env_from.config_map_ref`** | Injects every key in a ConfigMap as an environment variable inside the container |
| **Resource requests / limits** | `requests` guarantee scheduling headroom; `limits` cap CPU/memory — critical on small nodes like t3.small |

The Terraform `kubernetes` provider speaks directly to the Kubernetes API server. It reads the EKS cluster details using the `aws` provider, authenticates with a short-lived IAM-derived token, and then creates, updates, or deletes Kubernetes objects in exactly the same declarative manner as `kubectl apply` — except that Terraform also stores the state and can diff changes on the next `apply`.

---

## Prerequisite — Lab 033 Must Be Running

This lab **depends on Lab 033** (EKS cluster). Before continuing:

1. Lab 033 (`terraform-033-eks`) must be fully applied and the cluster must be in `ACTIVE` state.
2. Your local `kubectl` must already be configured for the cluster:

```bash
aws eks update-kubeconfig \
  --region ap-south-1 \
  --name terraform-033-eks
```

Verify connectivity before starting this lab:

```bash
kubectl get nodes
```

You should see at least one node in `Ready` state. If not, fix Lab 033 first.

---

## Architecture

```
                        ap-south-1
  ┌──────────────────────────────────────────────────────────────┐
  │                                                              │
  │   EKS Cluster: terraform-033-eks                            │
  │                                                              │
  │   Namespace: robochef                                        │
  │  ┌───────────────────────────────────────────────────────┐   │
  │  │                                                       │   │
  │  │  ConfigMap: robochef-config                           │   │
  │  │  ┌──────────────────────────────────────────────┐    │   │
  │  │  │  APP_ENV=production                           │    │   │
  │  │  │  APP_OWNER=saravanans                         │    │   │
  │  │  │  APP_PROJECT=robochef.co                      │    │   │
  │  │  │  APP_PORT=80                                  │    │   │
  │  │  └──────────────────────────────────────────────┘    │   │
  │  │            │ env_from                                 │   │
  │  │  Deployment: robochef-deployment (replicas: 2)        │   │
  │  │  ┌─────────────────────────────────────────────┐     │   │
  │  │  │  Pod 1: nginx:alpine (port 80)               │     │   │
  │  │  │  Pod 2: nginx:alpine (port 80)               │     │   │
  │  │  └─────────────────────────────────────────────┘     │   │
  │  │            │ selector: app=robochef                   │   │
  │  │  Service: robochef-service (ClusterIP: port 80)       │   │
  │  └───────────────────────────────────────────────────────┘   │
  │                                                              │
  └──────────────────────────────────────────────────────────────┘

  Terraform auth flow:
  aws provider → data.aws_eks_cluster (endpoint + CA cert)
              → data.aws_eks_cluster_auth (IAM token)
              → kubernetes provider → Kubernetes API
```

---

## What Terraform Creates

| # | Resource | Kubernetes name | Purpose |
|---|----------|----------------|---------|
| 1 | `kubernetes_namespace.app` | `robochef` | Isolation boundary for all app objects |
| 2 | `kubernetes_config_map.app` | `robochef/robochef-config` | Non-sensitive app config |
| 3 | `kubernetes_deployment.app` | `robochef/robochef-deployment` | 2-replica nginx:alpine deployment |
| 4 | `kubernetes_service.app` | `robochef/robochef-service` | ClusterIP service on port 80 |

---

## How the Kubernetes Provider Authenticates

When Terraform runs `terraform apply`, it executes the following sequence:

1. The `aws` provider reads `data "aws_eks_cluster"` — fetching the cluster's API server **endpoint** and **CA certificate**.
2. The `aws` provider reads `data "aws_eks_cluster_auth"` — calling the AWS STS token endpoint to produce a short-lived **bearer token** (valid for ~15 minutes) derived from your IAM identity.
3. The `kubernetes` provider is initialised with those three values: `host`, `cluster_ca_certificate`, and `token`.
4. Every subsequent `kubernetes_*` resource call uses that provider instance to talk to the EKS API server.

> You do not need a separate `~/.kube/config` entry. Terraform builds the credentials from IAM at runtime. This is why anyone with the right IAM permissions can run this Terraform without pre-configuring kubectl.

---

## Directory Layout

```
~/terraform-aws-k8s-034-demo/
├── providers.tf
├── variables.tf
├── main.tf
└── outputs.tf
```

---

## Step 1 — Create the Project Directory

```bash
mkdir ~/terraform-aws-k8s-034-demo
cd ~/terraform-aws-k8s-034-demo
```

---

## Step 2 — providers.tf

This file does two things: declares which providers are needed, and wires the EKS cluster details into the `kubernetes` provider.

```hcl
# providers.tf

terraform {
  required_version = ">= 1.3"
  required_providers {
    aws        = { source = "hashicorp/aws",        version = "~> 6.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.0" }
  }
}

provider "aws" { region = var.aws_region }

# Read the existing EKS cluster (created by Lab 033)
data "aws_eks_cluster" "this" { name = var.cluster_name }

# Generate a short-lived IAM bearer token for the Kubernetes API
data "aws_eks_cluster_auth" "this" { name = var.cluster_name }

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}
```

**Key points:**

- `data "aws_eks_cluster"` is a **read-only data source** — it does not create or modify the EKS cluster. It merely retrieves its attributes.
- `certificate_authority[0].data` is base64-encoded in the API response, so `base64decode()` is required.
- `data "aws_eks_cluster_auth"` uses your current AWS credentials (from environment variables or `~/.aws/credentials`) to call STS and produce the token. The token expires after about 15 minutes — Terraform refreshes it automatically on each run.

---

## Step 3 — variables.tf

```hcl
# variables.tf

variable "aws_region" {
  description = "AWS region where the EKS cluster lives"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster created in Lab 033"
  type        = string
  default     = "terraform-033-eks"
}

variable "app_name" {
  description = "Base name used for the Kubernetes namespace, deployment, service, and configmap"
  type        = string
  default     = "robochef"
}

variable "replicas" {
  description = "Number of pod replicas in the deployment"
  type        = number
  default     = 2
}
```

---

## Step 4 — main.tf

This file defines all four Kubernetes resources. Each resource references `var.app_name` so that changing one variable renames every object consistently.

```hcl
# main.tf

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

**Why `kubernetes_deployment` instead of `kubectl apply`?**

| Concern | `kubectl apply` | `terraform apply` |
|---------|----------------|-----------------|
| Diff before change | No (unless `--dry-run`) | Yes — always shows planned changes |
| State tracking | None | Full state file |
| Idempotency | Mostly (server-side apply) | Guaranteed |
| Rollback | `kubectl rollout undo` | `git revert` + `terraform apply` |
| Drift detection | No | `terraform plan` shows drift |

---

## Step 5 — outputs.tf

```hcl
# outputs.tf

output "namespace" {
  description = "Kubernetes namespace where all resources live"
  value       = kubernetes_namespace.app.metadata[0].name
}

output "deployment_name" {
  description = "Name of the Kubernetes deployment"
  value       = kubernetes_deployment.app.metadata[0].name
}

output "service_name" {
  description = "Name of the Kubernetes service"
  value       = kubernetes_service.app.metadata[0].name
}

output "verify_commands" {
  description = "kubectl commands to verify the deployment"
  value       = <<-EOT
    # List all resources in the namespace:
    kubectl get all -n ${kubernetes_namespace.app.metadata[0].name}

    # Inspect the pods:
    kubectl get pods -n ${kubernetes_namespace.app.metadata[0].name} -o wide

    # Inspect the ConfigMap:
    kubectl describe configmap ${kubernetes_config_map.app.metadata[0].name} \
      -n ${kubernetes_namespace.app.metadata[0].name}

    # Check environment variables inside a running pod:
    kubectl exec -n ${kubernetes_namespace.app.metadata[0].name} \
      deployment/${kubernetes_deployment.app.metadata[0].name} \
      -- env | grep APP_
  EOT
}
```

---

## Step 6 — Init and Plan

```bash
cd ~/terraform-aws-k8s-034-demo
terraform init
```

Expected output (providers downloaded):

```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Finding hashicorp/kubernetes versions matching "~> 2.0"...
- Installing hashicorp/aws v6.x.x...
- Installing hashicorp/kubernetes v2.x.x...

Terraform has been successfully initialized!
```

Run plan to preview what will be created:

```bash
terraform plan
```

You will see four resources to add:

```
Plan: 4 to add, 0 to change, 0 to destroy.
```

---

## Step 7 — Apply

```bash
terraform apply --auto-approve
```

**Actual verified output from the live demo:**

```
kubernetes_namespace.app: Creating...
kubernetes_namespace.app: Creation complete after 0s [id=robochef]
kubernetes_config_map.app: Creating...
kubernetes_config_map.app: Creation complete after 0s [id=robochef/robochef-config]
kubernetes_service.app: Creating...
kubernetes_service.app: Creation complete after 0s [id=robochef/robochef-service]
kubernetes_deployment.app: Creating...
kubernetes_deployment.app: Creation complete after 8s [id=robochef/robochef-deployment]

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

namespace       = "robochef"
deployment_name = "robochef-deployment"
service_name    = "robochef-service"
verify_commands = <<EOT
  # List all resources in the namespace:
  kubectl get all -n robochef
  ...
EOT
```

Notice the creation order: namespace first, then configmap and service (independent), then deployment last — Terraform resolves the dependency graph from the attribute references in `main.tf`.

---

## Step 8 — Verify with kubectl

```bash
kubectl get all -n robochef
```

**Actual verified output from the live demo:**

```
NAME                                      READY   STATUS    RESTARTS   AGE
pod/robochef-deployment-c5f68ffb4-7wvqh   1/1     Running   0          13s
pod/robochef-deployment-c5f68ffb4-pjllq   1/1     Running   0          13s

NAME                                  READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/robochef-deployment   2/2     2            2           13s

NAME                       TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/robochef-service   ClusterIP   10.100.57.18   <none>        80/TCP    13s
```

Both pods are `1/1 Running`. The deployment shows `2/2` available.

Inspect the ConfigMap values:

```bash
kubectl describe configmap robochef-config -n robochef
```

Verify the environment variables are injected into the pod:

```bash
kubectl exec -n robochef \
  deployment/robochef-deployment \
  -- env | grep APP_
```

Expected output:

```
APP_ENV=production
APP_OWNER=saravanans
APP_PROJECT=robochef.co
APP_PORT=80
```

---

## Step 9 — Scaling Demo (replicas 2 → 3)

One of Terraform's strengths with Kubernetes is declarative scaling. You change a single variable and Terraform reconciles the live cluster to match.

**Before scaling — check current pod count:**

```bash
kubectl get pods -n robochef
```

```
NAME                                      READY   STATUS    RESTARTS   AGE
pod/robochef-deployment-c5f68ffb4-7wvqh   1/1     Running   0          2m
pod/robochef-deployment-c5f68ffb4-pjllq   1/1     Running   0          2m
```

**Edit variables.tf** — change `replicas` from `2` to `3`:

```hcl
variable "replicas" {
  description = "Number of pod replicas in the deployment"
  type        = number
  default     = 3        # changed from 2 → 3
}
```

**Run plan to see what Terraform will do:**

```bash
terraform plan
```

Terraform shows an in-place update — only the replica count changes:

```
  # kubernetes_deployment.app will be updated in-place
  ~ resource "kubernetes_deployment" "app" {
      ~ spec {
          ~ replicas = 2 -> 3
        }
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

**Apply the change:**

```bash
terraform apply --auto-approve
```

```
kubernetes_deployment.app: Modifying... [id=robochef/robochef-deployment]
kubernetes_deployment.app: Modifications complete after 6s [id=robochef/robochef-deployment]

Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

**After scaling — verify the third pod appeared:**

```bash
kubectl get pods -n robochef
```

```
NAME                                      READY   STATUS    RESTARTS   AGE
pod/robochef-deployment-c5f68ffb4-7wvqh   1/1     Running   0          4m
pod/robochef-deployment-c5f68ffb4-pjllq   1/1     Running   0          4m
pod/robochef-deployment-c5f68ffb4-xk9mn   1/1     Running   0          18s
```

The third pod was scheduled and is now `Running`. No existing pods were restarted — Kubernetes only added the new replica.

**Scale back down to 2** by reverting `replicas` to `2` and running `terraform apply --auto-approve` again.

---

## Step 10 — Terraform vs kubectl: Drift Detection

A powerful advantage of managing Kubernetes via Terraform is drift detection. Simulate drift by scaling the deployment directly with kubectl (bypassing Terraform):

```bash
kubectl scale deployment robochef-deployment -n robochef --replicas=5
```

Now run `terraform plan`:

```bash
terraform plan
```

Terraform detects the live state (5 replicas) differs from the desired state (2 replicas) in the state file:

```
  # kubernetes_deployment.app will be updated in-place
  ~ resource "kubernetes_deployment" "app" {
      ~ spec {
          ~ replicas = 5 -> 2
        }
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

Running `terraform apply` restores the declared state. This is the key difference from `kubectl apply` alone — Terraform actively enforces the desired state on every apply.

---

## Concepts Deep Dive

### The Three Things the Kubernetes Provider Needs

| Parameter | Source | What it is |
|-----------|--------|-----------|
| `host` | `data.aws_eks_cluster.this.endpoint` | HTTPS URL of the Kubernetes API server |
| `cluster_ca_certificate` | `base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)` | PEM CA cert to verify TLS |
| `token` | `data.aws_eks_cluster_auth.this.token` | Short-lived bearer token from AWS STS |

Without all three, every `kubernetes_*` resource call will fail with a connection or authentication error.

### Why the Token is Short-Lived

`data "aws_eks_cluster_auth"` internally calls `aws eks get-token`. This generates a pre-signed STS URL that the Kubernetes API server validates against IAM. The token expires in approximately 15 minutes. Terraform fetches a fresh token at the start of each `terraform apply` or `terraform plan`, so this expiry is transparent during normal usage.

### Resource Requests vs Limits (t3.small Context)

A t3.small node has 2 vCPU and 2 GB RAM. Kubernetes reserves headroom for system processes, leaving roughly 1.7 vCPU and 1.6 GB for pods. With:

```
requests: cpu=50m, memory=64Mi
limits:   cpu=100m, memory=128Mi
```

Each nginx:alpine pod requests only 50 millicores (0.05 vCPU) and 64 MiB. Two pods consume just 100m CPU / 128 MiB RAM in requests — well within the node capacity. Omitting resource limits on shared lab nodes can cause one pod to starve others, so always set them in lab environments.

### `env_from.config_map_ref` vs Individual `env` blocks

| Approach | When to use |
|----------|------------|
| `env_from.config_map_ref` | Inject all keys from a ConfigMap at once — ideal when the ConfigMap grows |
| `env { name = "X" valueFrom ... }` | Map individual ConfigMap keys to specific env var names — ideal for precise control |

This lab uses `env_from` for simplicity. Adding a new key to `kubernetes_config_map.app.data` automatically makes it available as an env var in the container after the next `terraform apply`.

---

## Cleanup Order — Important

You must destroy this lab **before** destroying the EKS cluster from Lab 033. Destroying in the wrong order will leave orphaned Kubernetes resources in a cluster that no longer exists, and Terraform state will be corrupted.

### Step 1 — Destroy Lab 034 (this lab) first

```bash
cd ~/terraform-aws-k8s-034-demo
terraform destroy --auto-approve
rm -rf .terraform
```

Expected output:

```
kubernetes_deployment.app: Destroying... [id=robochef/robochef-deployment]
kubernetes_deployment.app: Destruction complete after 8s
kubernetes_service.app: Destroying... [id=robochef/robochef-service]
kubernetes_service.app: Destruction complete after 0s
kubernetes_config_map.app: Destroying... [id=robochef/robochef-config]
kubernetes_config_map.app: Destruction complete after 0s
kubernetes_namespace.app: Destroying... [id=robochef]
kubernetes_namespace.app: Destruction complete after 5s

Destroy complete! Resources: 4 destroyed.
```

Verify the namespace is gone:

```bash
kubectl get namespace robochef
```

Expected: `Error from server (NotFound): namespaces "robochef" not found`

### Step 2 — Destroy Lab 033 (EKS cluster) second

```bash
cd ~/terraform-aws-eks-033-demo
terraform destroy --auto-approve
rm -rf .terraform
```

This will remove the EKS cluster, node group, VPC, subnets, and all associated resources. This step takes 10-15 minutes.

---

## Quick Reference

| Task | Command |
|------|---------|
| Initialise providers | `terraform init` |
| Preview changes | `terraform plan` |
| Apply changes | `terraform apply --auto-approve` |
| List all resources in namespace | `kubectl get all -n robochef` |
| Describe ConfigMap | `kubectl describe configmap robochef-config -n robochef` |
| Check pod env vars | `kubectl exec -n robochef deployment/robochef-deployment -- env \| grep APP_` |
| Scale via Terraform | Edit `replicas` in `variables.tf`, then `terraform apply --auto-approve` |
| Destroy (this lab) | `terraform destroy --auto-approve && rm -rf .terraform` |
| Destroy (EKS, Lab 033) | `cd ~/terraform-aws-eks-033-demo && terraform destroy --auto-approve && rm -rf .terraform` |

---

## Summary

| What was done | Why it matters |
|--------------|---------------|
| Used `data "aws_eks_cluster"` and `data "aws_eks_cluster_auth"` to wire the kubernetes provider | No kubeconfig file or manual credential setup required — IAM drives authentication |
| Created a namespace, configmap, deployment, and service as Terraform resources | All Kubernetes objects are version-controlled, diffable, and state-tracked |
| Used `env_from.config_map_ref` to inject config into the container | Decouples configuration from the container image — change config without rebuilding |
| Set resource requests and limits | Ensures reliable scheduling on constrained lab nodes (t3.small) |
| Demonstrated declarative scaling by changing `replicas` | Shows Terraform computing the minimal in-place patch rather than destroying/recreating |
| Demonstrated drift detection | Shows Terraform's advantage over raw `kubectl apply` for enforcement |
| Destroyed Lab 034 before Lab 033 | Correct dependency ordering prevents state corruption |
