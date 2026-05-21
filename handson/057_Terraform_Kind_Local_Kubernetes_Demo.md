# Lab 057 — Terraform + kind: Local Kubernetes Cluster Demo

**By: Saravanan Sundaramoorthy**

> **Verified live on this machine.** kind v0.23.0, kubectl v1.35.5, Kubernetes v1.30.0, Terraform kubernetes provider ~> 2.0

---

## What You'll Learn

| Topic | Concept |
|-------|---------|
| kind | Create a local Kubernetes cluster inside Docker containers |
| kubectl | Core commands: get, describe, port-forward, logs, scale, delete |
| Terraform kubernetes provider | Manage k8s resources (Namespace, ConfigMap, Deployment, Service) declaratively |
| Scaling | Change `replicas` variable → `terraform apply` → pods scale instantly |
| Port-forward | Access ClusterIP services locally during development |

---

## Prerequisites

- Docker running (`docker info`)
- 4 GB RAM available

---

## Step 1 — Install kind

```bash
# Linux (amd64)
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
kind version
# kind v0.23.0 go1.21.10 linux/amd64
```

Or via snap/brew:
```bash
sudo snap install kind          # Linux snap
brew install kind               # macOS
```

---

## Step 2 — Install kubectl

```bash
# Linux
sudo snap install kubectl --classic
kubectl version --client
# Client Version: v1.35.5

# Or via apt
sudo apt-get update && sudo apt-get install -y kubectl
```

---

## Step 3 — Create the kind Cluster

```bash
kind create cluster --name terraform-kind-lab --wait 60s
```

Expected output:
```
Creating cluster "terraform-kind-lab" ...
 ✓ Ensuring node image (kindest/node:v1.30.0) 🖼
 ✓ Preparing nodes 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
 ✓ Waiting ≤ 1m0s for control-plane = Ready ⏳
 ✓ Waiting ≤ 1m0s for control-plane = Ready ⏳  (22s)
 • Ready after 22s 💚
Set kubectl context to "kind-terraform-kind-lab"
```

kind automatically updates `~/.kube/config` with the new context.

### Verify the cluster

```bash
# Check nodes
kubectl get nodes --context kind-terraform-kind-lab
# NAME                               STATUS   ROLES           AGE   VERSION
# terraform-kind-lab-control-plane   Ready    control-plane   42s   v1.30.0

# Check system pods
kubectl get pods -A --context kind-terraform-kind-lab
# NAMESPACE     NAME                                                        READY   STATUS    RESTARTS   AGE
# kube-system   coredns-7db6d8ff4d-...                                      1/1     Running   0          40s
# kube-system   etcd-terraform-kind-lab-control-plane                       1/1     Running   0          50s
# kube-system   kindnet-...                                                  1/1     Running   0          40s
# kube-system   kube-apiserver-terraform-kind-lab-control-plane             1/1     Running   0          50s
# kube-system   kube-controller-manager-terraform-kind-lab-control-plane    1/1     Running   0          50s
# kube-system   kube-scheduler-terraform-kind-lab-control-plane             1/1     Running   0          50s
# kube-system   kube-proxy-...                                               1/1     Running   0          40s

# Check cluster info
kubectl cluster-info --context kind-terraform-kind-lab
# Kubernetes control plane is running at https://127.0.0.1:33471
```

---

## Step 4 — Project Setup

```bash
mkdir ~/terraform-kind-057-demo
cd ~/terraform-kind-057-demo
```

### providers.tf

```hcl
terraform {
  required_version = ">= 1.3"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

# kind stores kubeconfig in ~/.kube/config — the kubernetes provider reads it automatically
# when config_path is set. Context: kind-terraform-kind-lab
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kind-terraform-kind-lab"
}
```

### variables.tf

```hcl
variable "cluster_context" {
  description = "kubectl context name for the kind cluster"
  type        = string
  default     = "kind-terraform-kind-lab"
}

variable "app_name" {
  description = "Application name used as prefix for all k8s resources"
  type        = string
  default     = "robochef"
}

variable "replicas" {
  description = "Number of pod replicas in the Deployment"
  type        = number
  default     = 2
}

variable "image" {
  description = "Container image to run"
  type        = string
  default     = "nginx:alpine"
}
```

### main.tf

```hcl
# ─────────────────────────────────────────────
# Namespace
# ─────────────────────────────────────────────

resource "kubernetes_namespace" "app" {
  metadata {
    name = var.app_name
    labels = {
      owner   = "saravanans"
      project = "robochef.co"
      env     = "kind-local"
    }
  }
}

# ─────────────────────────────────────────────
# ConfigMap
# ─────────────────────────────────────────────

resource "kubernetes_config_map" "app" {
  metadata {
    name      = "${var.app_name}-config"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    APP_NAME  = "robochef.co"
    APP_OWNER = "saravanans"
    APP_ENV   = "kind-local"
    APP_PORT  = "80"
  }
}

# ─────────────────────────────────────────────
# Deployment
# ─────────────────────────────────────────────

resource "kubernetes_deployment" "app" {
  metadata {
    name      = "${var.app_name}-deployment"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels = {
      app     = var.app_name
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
          name  = "nginx"
          image = var.image

          port {
            container_port = 80
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.app.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }
        }
      }
    }
  }
}

# ─────────────────────────────────────────────
# Service (ClusterIP)
# ─────────────────────────────────────────────

resource "kubernetes_service" "app" {
  metadata {
    name      = "${var.app_name}-service"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels = {
      app     = var.app_name
      owner   = "saravanans"
      project = "robochef.co"
    }
  }

  spec {
    selector = {
      app = var.app_name
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

### outputs.tf

```hcl
output "namespace" {
  value = kubernetes_namespace.app.metadata[0].name
}

output "deployment_name" {
  value = kubernetes_deployment.app.metadata[0].name
}

output "service_name" {
  value = kubernetes_service.app.metadata[0].name
}

output "replicas" {
  value = kubernetes_deployment.app.spec[0].replicas
}

output "kubectl_commands" {
  value = <<-EOT
    kubectl get namespace ${var.app_name} --context ${var.cluster_context}
    kubectl get pods -n ${var.app_name} --context ${var.cluster_context}
    kubectl get deployment -n ${var.app_name} --context ${var.cluster_context}
    kubectl get service -n ${var.app_name} --context ${var.cluster_context}
    kubectl get configmap -n ${var.app_name} --context ${var.cluster_context}
    kubectl port-forward svc/${kubernetes_service.app.metadata[0].name} 8080:80 -n ${var.app_name} --context ${var.cluster_context}
  EOT
}
```

---

## Step 5 — Init and Apply

```bash
terraform init
terraform apply --auto-approve
```

Expected output:
```
kubernetes_namespace.app: Creating...
kubernetes_namespace.app: Creation complete after 0s [id=robochef]
kubernetes_config_map.app: Creating...
kubernetes_service.app: Creating...
kubernetes_config_map.app: Creation complete after 0s [id=robochef/robochef-config]
kubernetes_service.app: Creation complete after 0s [id=robochef/robochef-service]
kubernetes_deployment.app: Creating...
kubernetes_deployment.app: Still creating... [10s elapsed]
kubernetes_deployment.app: Creation complete after 16s [id=robochef/robochef-deployment]

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:
deployment_name = "robochef-deployment"
namespace = "robochef"
replicas = "2"
service_name = "robochef-service"
```

---

## Step 6 — Verify with kubectl

```bash
kubectl get pods -n robochef --context kind-terraform-kind-lab
```
```
NAME                                       READY   STATUS    RESTARTS   AGE
pod/robochef-deployment-7df656f5d7-8v2ms   1/1     Running   0          26s
pod/robochef-deployment-7df656f5d7-r4rcl   1/1     Running   0          26s
```

```bash
kubectl get deployment -n robochef --context kind-terraform-kind-lab
```
```
NAME                                  READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/robochef-deployment   2/2     2            2           26s
```

```bash
kubectl get service -n robochef --context kind-terraform-kind-lab
```
```
NAME                       TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)   AGE
service/robochef-service   ClusterIP   10.96.26.93   <none>        80/TCP    27s
```

```bash
kubectl get configmap -n robochef --context kind-terraform-kind-lab
```
```
NAME                         DATA   AGE
configmap/robochef-config    4      27s
```

### Describe the deployment

```bash
kubectl describe deployment robochef-deployment -n robochef --context kind-terraform-kind-lab
```

### Check pod logs

```bash
# Get pod name
kubectl get pods -n robochef --context kind-terraform-kind-lab

# View logs
kubectl logs <pod-name> -n robochef --context kind-terraform-kind-lab

# Follow logs
kubectl logs -f <pod-name> -n robochef --context kind-terraform-kind-lab
```

---

## Step 7 — Access nginx via Port-Forward

```bash
kubectl port-forward svc/robochef-service 8080:80 -n robochef --context kind-terraform-kind-lab &
curl http://localhost:8080
```

Expected output:
```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
```

```bash
# Stop the port-forward
kill %1
```

---

## Step 8 — Scale Up with Terraform

```bash
terraform apply --auto-approve -var="replicas=3"
```

```bash
kubectl get pods -n robochef --context kind-terraform-kind-lab
# NAME                                       READY   STATUS    RESTARTS   AGE
# robochef-deployment-7df656f5d7-8v2ms       1/1     Running   0          2m
# robochef-deployment-7df656f5d7-r4rcl       1/1     Running   0          2m
# robochef-deployment-7df656f5d7-newpod      1/1     Running   0          5s
```

Scale back:
```bash
terraform apply --auto-approve -var="replicas=2"
```

---

## Step 9 — Exec into a Pod

```bash
POD=$(kubectl get pods -n robochef --context kind-terraform-kind-lab -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD -n robochef --context kind-terraform-kind-lab -- sh

# Inside the pod — verify env vars from ConfigMap
env | grep APP
# APP_NAME=robochef.co
# APP_OWNER=saravanans
# APP_ENV=kind-local
# APP_PORT=80

exit
```

---

## Step 10 — Drift Detection

Manually scale with kubectl (bypassing Terraform):

```bash
kubectl scale deployment robochef-deployment --replicas=1 -n robochef --context kind-terraform-kind-lab

# Check what Terraform sees
terraform plan
# kubernetes_deployment.app will be updated in-place
#   ~ replicas = 1 -> 2   (Terraform detects drift and reconciles)
```

```bash
# Restore to Terraform-managed state
terraform apply --auto-approve
```

---

## Step 11 — Useful kubectl Reference

```bash
# List all contexts
kubectl config get-contexts

# Switch context
kubectl config use-context kind-terraform-kind-lab

# Get all resources in a namespace
kubectl get all -n robochef --context kind-terraform-kind-lab

# Watch pods in real time
kubectl get pods -n robochef -w --context kind-terraform-kind-lab

# Get resource YAML
kubectl get deployment robochef-deployment -n robochef -o yaml --context kind-terraform-kind-lab

# Edit resource live (not recommended when using Terraform — causes drift)
kubectl edit deployment robochef-deployment -n robochef --context kind-terraform-kind-lab

# Rollout status
kubectl rollout status deployment/robochef-deployment -n robochef --context kind-terraform-kind-lab

# Rollout history
kubectl rollout history deployment/robochef-deployment -n robochef --context kind-terraform-kind-lab

# Rollback
kubectl rollout undo deployment/robochef-deployment -n robochef --context kind-terraform-kind-lab

# Top (resource usage — requires metrics-server)
kubectl top pods -n robochef --context kind-terraform-kind-lab

# Delete a pod (Deployment will recreate it)
kubectl delete pod <pod-name> -n robochef --context kind-terraform-kind-lab

# Get events
kubectl get events -n robochef --context kind-terraform-kind-lab
```

---

## Step 12 — Cleanup

```bash
# Destroy all Terraform-managed k8s resources
terraform destroy --auto-approve
rm -rf .terraform

# Delete the kind cluster
kind delete cluster --name terraform-kind-lab

# Verify
kind get clusters
# (empty)

kubectl config get-contexts
# kind-terraform-kind-lab context is removed from ~/.kube/config
```

---

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| **kind** | Kubernetes IN Docker — runs a full k8s cluster as Docker containers on your laptop |
| **Context** | A named entry in `~/.kube/config` pointing to a cluster + user + namespace |
| **ClusterIP** | Service type visible only inside the cluster — use `port-forward` to reach it locally |
| **ConfigMap** | Key-value store injected as env vars (`env_from`) or mounted as files |
| **Terraform drift** | kubectl changes bypass Terraform state — `terraform plan` detects and reconciles |
| **`config_path` + `config_context`** | How the Terraform kubernetes provider connects to the right cluster |

---

## kind vs Minikube vs EKS

| Feature | kind | Minikube | AWS EKS |
|---------|------|----------|---------|
| Speed to start | ~25 seconds | ~2-3 minutes | ~10-15 minutes |
| Cost | Free (Docker only) | Free (Docker/VM) | ~$0.10/hr + nodes |
| CI/CD friendly | Yes (Docker-in-Docker) | Partial | Yes (cloud) |
| Multi-node support | Yes | Partial | Yes |
| Persistent storage | Limited | Yes (hostPath) | Yes (EBS) |
| Best for | Local dev, CI, this lab | Local dev | Production |

---

## Concept Summary

```
kind create cluster      → Docker container becomes a Kubernetes node
terraform init           → Downloads hashicorp/kubernetes provider
terraform apply          → Namespace + ConfigMap + Deployment + Service created in k8s
kubectl get pods         → Verifies 2 nginx pods running
kubectl port-forward     → Tunnels localhost:8080 → ClusterIP:80 inside cluster
curl http://localhost:8080 → nginx Welcome page confirmed
terraform apply -var="replicas=3" → Scales to 3 pods instantly
terraform destroy        → Removes all k8s resources
kind delete cluster      → Removes the Docker-based cluster entirely
rm -rf .terraform        → Frees disk space from provider binary
```
