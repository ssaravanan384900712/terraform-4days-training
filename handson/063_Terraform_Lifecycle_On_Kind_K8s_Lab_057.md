# Lab 063 — Terraform Lifecycle Meta-Arguments on kind Kubernetes (Lab 057)

**By: Saravanan Sundaramoorthy**
**Environment:** Ubuntu Linux — requires kind v0.23.0, kubectl, Terraform ≥ 1.3
**Prerequisites:** Lab 057 completed — `~/terraform-kind-057-demo/` must exist and the kind cluster must be running
**Time:** ~30 minutes

---

## What You'll Learn

| Lifecycle setting | Applied to | What it demonstrates |
|-------------------|-----------|----------------------|
| `create_before_destroy` | `kubernetes_namespace` | New namespace created before old one is destroyed during replacement |
| `prevent_destroy` | `kubernetes_config_map` | Terraform refuses to delete the ConfigMap — simulates protecting prod config |
| `ignore_changes` | `kubernetes_deployment` | External `kubectl scale` drift is tolerated — Terraform stops reverting replica count |
| `replace_triggered_by` | `kubernetes_deployment` | Deployment is force-replaced whenever the ConfigMap changes |

Lab 037 covered lifecycle on `local_file` and `random` resources. This lab applies the same four settings to **live Kubernetes resources on a real kind cluster** so you see what each setting does to actual pods and namespaces.

---

## Concept Recap

Every Terraform resource follows: **create → update → destroy**. The `lifecycle` block overrides that default:

```
Default k8s resource lifecycle (no lifecycle block):
  create  → namespace / configmap / deployment / service created
  update  → patched in-place (e.g. replicas: 2 → 3)
  destroy → removed from the cluster

lifecycle block overrides:
  create_before_destroy  → spin up replacement before tearing down old
  prevent_destroy        → hard error at plan time if destroy is attempted
  ignore_changes         → skip listed attributes when detecting drift
  replace_triggered_by   → force full replacement when a dependency changes
```

---

## Prerequisites — Cluster Running

```bash
kind get clusters
# terraform-kind-lab   ← must be present
```

If not running:
```bash
kind create cluster --name terraform-kind-lab --wait 60s
```

Work in a copy of the lab-057 project so the original is untouched:

```bash
cp -r ~/terraform-kind-057-demo ~/terraform-kind-063-lifecycle-demo
cd ~/terraform-kind-063-lifecycle-demo
terraform init
```

---

## Part 1 — `create_before_destroy` on Namespace

### The problem

When Terraform needs to **replace** a resource (destroy + recreate), the default order is destroy-first. For a Kubernetes namespace that contains running pods, destroy-first means all workloads are deleted before the new namespace exists — a gap where nothing is running.

`create_before_destroy = true` reverses the order: the new namespace is created first, then the old one is destroyed.

### Add the lifecycle block to `main.tf`

Open `~/terraform-kind-063-lifecycle-demo/main.tf` and update the namespace resource:

```hcl
resource "kubernetes_namespace" "app" {
  metadata {
    name = var.app_name
    labels = {
      owner   = "saravanans"
      project = "robochef.co"
      env     = "kind-local"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}
```

### Trigger a replacement

A namespace is replaced (not updated) when its `name` changes. Apply with a different `app_name`:

```bash
terraform apply --auto-approve -var="app_name=robochef-v2"
```

Watch the plan output — Terraform creates `robochef-v2` namespace **before** destroying `robochef`:

```
kubernetes_namespace.app: Creating... [name=robochef-v2]
kubernetes_namespace.app: Creation complete after 0s [id=robochef-v2]
kubernetes_namespace.app (destroy): Destroying... [id=robochef]
kubernetes_namespace.app: Destruction complete after 0s
```

Without `create_before_destroy` the output would be reversed:
```
# destroy first, then create — gap where no namespace exists
kubernetes_namespace.app (destroy): Destroying... [id=robochef]
kubernetes_namespace.app: Destruction complete after 0s
kubernetes_namespace.app: Creating... [name=robochef-v2]
```

Restore original name before continuing:
```bash
terraform apply --auto-approve -var="app_name=robochef"
```

---

## Part 2 — `prevent_destroy` on ConfigMap

### The problem

The ConfigMap holds application configuration. Accidentally running `terraform destroy` on a production cluster should fail loudly rather than silently deleting config that pods depend on.

`prevent_destroy = true` makes Terraform raise a hard error at plan time if anything would cause the resource to be destroyed.

### Add the lifecycle block

```hcl
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
    APP_NAME  = "robochef.co"
    APP_OWNER = "saravanans"
    APP_ENV   = "kind-local"
    APP_PORT  = "80"
  }

  lifecycle {
    prevent_destroy = true
  }
}
```

```bash
terraform apply --auto-approve
```

### Trigger the guard

Try to destroy all resources:

```bash
terraform destroy --auto-approve
```

Expected error — Terraform refuses before touching the cluster:

```
╷
│ Error: Instance cannot be destroyed
│
│   on main.tf line 20, in resource "kubernetes_config_map" "app":
│   20:     prevent_destroy = true
│
│ Resource kubernetes_config_map.app has lifecycle.prevent_destroy set,
│ but the plan calls for this resource to be destroyed. To allow
│ destruction of this resource, remove the lifecycle.prevent_destroy
│ block, or set it to false, then run Terraform again.
╵
```

The **namespace, deployment, and service are not touched** — Terraform aborts the entire destroy when it encounters the protected resource.

To proceed with cleanup, remove or set `prevent_destroy = false` first.

---

## Part 3 — `ignore_changes` on Deployment Replicas

### The problem

The SRE team scales the Deployment with `kubectl scale` during an incident — bypassing Terraform. Next time a developer runs `terraform apply` (for an unrelated change), Terraform detects the drift and reverts the replica count back, undoing the SRE's change.

`ignore_changes = [spec[0].replicas]` tells Terraform to stop tracking that attribute — external changes to replica count are accepted as permanent.

### Add the lifecycle block

```hcl
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
    replicas = var.replicas   # Terraform sets this on create only

    selector {
      match_labels = { app = var.app_name }
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
          image = var.image

          port { container_port = 80 }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.app.metadata[0].name
            }
          }

          resources {
            requests = { cpu = "50m",  memory = "32Mi" }
            limits   = { cpu = "100m", memory = "64Mi" }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      spec[0].replicas,   # tolerate external kubectl scale changes
    ]
  }
}
```

```bash
terraform apply --auto-approve
```

### Simulate external drift — kubectl scale

```bash
kubectl scale deployment robochef-deployment --replicas=4 \
  -n robochef --context kind-terraform-kind-lab

kubectl get pods -n robochef --context kind-terraform-kind-lab
# 4 pods running
```

### Run terraform plan — drift is ignored

```bash
terraform plan
```

Expected — Terraform sees **no changes** to the deployment, even though the cluster has 4 replicas and `variables.tf` has `default = 2`:

```
kubernetes_namespace.app: Refreshing state...
kubernetes_config_map.app: Refreshing state...
kubernetes_deployment.app: Refreshing state...
kubernetes_service.app: Refreshing state...

No changes. Your infrastructure matches the configuration.
```

Without `ignore_changes`, the plan would show:
```
~ spec[0].replicas = 4 -> 2   ← Terraform would revert the SRE's change
```

---

## Part 4 — `replace_triggered_by` on Deployment

### The problem

The Deployment mounts a ConfigMap via `env_from`. Kubernetes does **not** automatically restart pods when a ConfigMap changes — pods keep running with the old env values. To force a rolling restart when config changes, the Deployment itself must be replaced.

`replace_triggered_by = [kubernetes_config_map.app]` tells Terraform: whenever the ConfigMap is replaced, force-replace the Deployment too.

### Add the lifecycle block

```hcl
resource "kubernetes_deployment" "app" {
  # ... (same spec as Part 3) ...

  lifecycle {
    ignore_changes = [
      spec[0].replicas,
    ]
    replace_triggered_by = [
      kubernetes_config_map.app,   # replace deployment whenever configmap is replaced
    ]
  }
}
```

### Trigger a ConfigMap replacement

Change a ConfigMap value so Terraform replaces it (ConfigMaps are replaced, not patched, when `name` or `namespace` changes; in-place data changes are patched, so for this demo force replacement by changing the name suffix):

Or, simulate the cascade by changing a data key that causes the Deployment to re-read config:

```bash
# Edit main.tf — add a new key to the ConfigMap data block
# APP_VERSION = "v2"
```

```bash
terraform apply --auto-approve
```

Expected plan output — ConfigMap is updated in-place AND Deployment is force-replaced:

```
kubernetes_config_map.app: Modifying... [id=robochef/robochef-config]
kubernetes_config_map.app: Modifications complete after 0s

kubernetes_deployment.app: Replacing... (replace_triggered_by)
kubernetes_deployment.app (deposed): Destroying... [id=robochef/robochef-deployment]
kubernetes_deployment.app: Creating...
kubernetes_deployment.app: Creation complete after 12s [id=robochef/robochef-deployment]
```

The Deployment is fully re-created — all pods restart and pick up the new ConfigMap values.

```bash
# Verify pods restarted — AGE should be seconds
kubectl get pods -n robochef --context kind-terraform-kind-lab
# NAME                                      READY   STATUS    RESTARTS   AGE
# robochef-deployment-xxxxxxxxx-zzzzz       1/1     Running   0          8s
```

---

## All Four Together — `main.tf` (Final State)

```hcl
resource "kubernetes_namespace" "app" {
  metadata {
    name = var.app_name
    labels = {
      owner   = "saravanans"
      project = "robochef.co"
      env     = "kind-local"
    }
  }

  lifecycle {
    create_before_destroy = true   # new ns exists before old is gone
  }
}

resource "kubernetes_config_map" "app" {
  metadata {
    name      = "${var.app_name}-config"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = { owner = "saravanans", project = "robochef.co" }
  }

  data = {
    APP_NAME    = "robochef.co"
    APP_OWNER   = "saravanans"
    APP_ENV     = "kind-local"
    APP_PORT    = "80"
    APP_VERSION = "v2"
  }

  lifecycle {
    prevent_destroy = true         # hard error if anything tries to destroy this
  }
}

resource "kubernetes_deployment" "app" {
  metadata {
    name      = "${var.app_name}-deployment"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = { owner = "saravanans", project = "robochef.co" }
  }

  spec {
    replicas = var.replicas
    selector { match_labels = { app = var.app_name } }
    template {
      metadata { labels = { app = var.app_name, owner = "saravanans", project = "robochef.co" } }
      spec {
        container {
          name  = var.app_name
          image = var.image
          port  { container_port = 80 }
          env_from { config_map_ref { name = kubernetes_config_map.app.metadata[0].name } }
          resources {
            requests = { cpu = "50m",  memory = "32Mi" }
            limits   = { cpu = "100m", memory = "64Mi" }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes       = [spec[0].replicas]          # tolerate kubectl scale drift
    replace_triggered_by = [kubernetes_config_map.app] # restart pods on config change
  }
}

resource "kubernetes_service" "app" {
  metadata {
    name      = "${var.app_name}-service"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = { owner = "saravanans", project = "robochef.co" }
  }
  spec {
    type     = "ClusterIP"
    selector = { app = var.app_name }
    port     { port = 80; target_port = 80; protocol = "TCP" }
  }
}
```

---

## Behaviour Summary

| Setting | Kubernetes effect | Without it |
|---------|-------------------|------------|
| `create_before_destroy` on Namespace | New namespace + pods spin up before old namespace is deleted | Gap: old namespace gone, new not yet ready |
| `prevent_destroy` on ConfigMap | `terraform destroy` aborted at plan — ConfigMap never touched | ConfigMap silently deleted with everything else |
| `ignore_changes = [spec[0].replicas]` on Deployment | `kubectl scale` changes are permanent — `terraform plan` shows no diff | Every `terraform apply` reverts to the declared replica count |
| `replace_triggered_by = [configmap]` on Deployment | Pods force-restart when ConfigMap is replaced | Pods keep running with stale env vars after config changes |

---

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| **Replacement vs update** | A resource is replaced (destroy + create) when an immutable field changes; updated in-place otherwise. `lifecycle` controls the order and conditions of replacement. |
| **`create_before_destroy`** | Reverses the replace order — create first, destroy second. Essential for resources others depend on (namespaces, certificates, VPCs). |
| **`prevent_destroy`** | A plan-time guard, not a runtime lock. It blocks `terraform destroy` and any plan that includes destroying the resource. Remove the flag to unblock. |
| **`ignore_changes`** | The listed attributes are excluded from drift detection. Terraform never generates a diff for them — whatever is in the cluster is accepted as ground truth. |
| **`replace_triggered_by`** | Adds an implicit dependency for replacement. When the referenced resource is replaced or modified, this resource is also replaced — even if its own config hasn't changed. |

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Instance cannot be destroyed` | `prevent_destroy = true` is set | Remove or set `= false`, then re-run |
| Plan reverts `kubectl scale` changes | `ignore_changes` not set on `spec[0].replicas` | Add `ignore_changes = [spec[0].replicas]` to the Deployment lifecycle block |
| Pods not restarting after ConfigMap change | `replace_triggered_by` not set | Add `replace_triggered_by = [kubernetes_config_map.app]` to Deployment lifecycle |
| `create_before_destroy` conflict | Two resources with same name exist simultaneously | Use a unique name during transition (e.g. suffix with `-v2`) |

---

## Cleanup

First remove `prevent_destroy` from the ConfigMap (otherwise destroy will fail):

```hcl
lifecycle {
  prevent_destroy = false
}
```

```bash
terraform apply --auto-approve   # update state with prevent_destroy removed
terraform destroy --auto-approve
rm -rf .terraform
```

Delete the kind cluster if finished with all kind labs:
```bash
kind delete cluster --name terraform-kind-lab
```

---

## Concept Summary

```
create_before_destroy = true
  → kubernetes_namespace: new ns ready before old ns is gone
  → use on any resource that other resources depend on during replacement

prevent_destroy = true
  → kubernetes_config_map: terraform destroy aborted at plan time
  → remove the flag to actually destroy — acts as a manual safety gate

ignore_changes = [spec[0].replicas]
  → kubernetes_deployment: kubectl scale changes are tolerated permanently
  → Terraform stops tracking that attribute — plan always shows "no changes" for it

replace_triggered_by = [kubernetes_config_map.app]
  → kubernetes_deployment: pods force-restart whenever configmap is replaced
  → solves the Kubernetes env-var stale-config problem declaratively
```
