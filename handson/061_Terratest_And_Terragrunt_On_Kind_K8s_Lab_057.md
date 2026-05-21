# Lab 061 — Terratest and Terragrunt Applied to the kind Kubernetes Lab (057)

**By: Saravanan Sundaramoorthy**
**Environment:** Ubuntu Linux — requires kind v0.23.0, kubectl, Go 1.21+, Terraform ≥ 1.3
**Prerequisites:** Lab 057 completed — `~/terraform-kind-057-demo/` must exist
**Time:** ~45 minutes

---

## What You'll Learn

| Topic | Concept |
|-------|---------|
| Terratest | Write Go integration tests that call `terraform apply`, query the live kind cluster, and assert correctness |
| `k8s` Terratest module | Use `k8s.GetNamespace`, `k8s.ListPods`, `k8s.GetService` to verify live resources |
| Terragrunt | Wrap the lab-057 kind module for two environments (dev, prod) with DRY config |
| `terragrunt run-all` | Apply/destroy all environments in one command |
| `dependency {}` block | Chain environment outputs when one Terragrunt unit depends on another |

Lab 057 created a kind cluster with a Namespace, ConfigMap, Deployment, and Service using the `hashicorp/kubernetes` provider. This lab treats that project as a **module** and adds:

1. **Terratest** — a Go test that applies the module, hits the live cluster, verifies the pods are Running, then tears down
2. **Terragrunt** — a DRY wrapper that calls the same module for `dev` and `prod` with different replica counts and app names

---

## Introduction to Terratest

Terraform configs are code — and code needs tests. The problem with Terraform is that a `terraform validate` or even a `terraform plan` cannot tell you whether your infrastructure actually **works**: whether the pods come up, whether the service routes traffic, whether the ConfigMap keys are correct.

**Terratest** is a Go library by Gruntwork that solves this. It performs real integration tests by:

1. Calling `terraform apply` against real providers (AWS, Kubernetes, local, etc.)
2. Letting you write assertions against the live infrastructure using helper modules (`k8s`, `aws`, `http`, etc.)
3. Always cleaning up via `defer terraform.Destroy()` — even if the test panics

```
Traditional approach              Terratest approach
──────────────────────────        ──────────────────────────────────────────
terraform apply                   go test ./...
  ↓                                 ↓
Manual: kubectl get pods            terraform.InitAndApply(t, tfOpts)
Manual: check logs                  k8s.WaitUntilPodAvailable(...)   ← live assertion
Manual: curl service                k8s.GetService(...)              ← live assertion
Manual: terraform destroy           defer terraform.Destroy(t, opts) ← guaranteed cleanup
```

Why Go? Because Go has first-class concurrency (run many test environments in parallel with `t.Parallel()`), a fast compiler, and Gruntwork's `terratest` package covers every major Terraform provider.

| Terratest concept | Meaning |
|-------------------|---------|
| `terraform.Options` | Struct: TerraformDir, Vars, EnvVars, Logger — one per test |
| `terraform.InitAndApply` | Runs `terraform init` then `terraform apply --auto-approve` |
| `terraform.Output` | Reads a named output from the applied state |
| `terraform.Destroy` | Runs `terraform destroy --auto-approve` — always deferred |
| `k8s.NewKubectlOptions` | Creates a kubectl context: cluster name, kubeconfig, namespace |
| `k8s.WaitUntilPodAvailable` | Polls with retries until pod status = Ready |
| `k8s.GetService` | Fetches the live Service object for assertion |
| `k8s.GetConfigMap` | Fetches the live ConfigMap — assert on `.Data["key"]` |

---

## Introduction to Terragrunt

When you have one Terraform module and need to deploy it to **multiple environments** (dev, staging, prod), the naive approach is to copy the `.tf` files into each environment directory. You end up with identical `versions.tf`, `providers.tf`, and `backend.tf` in every folder — a maintenance nightmare.

**Terragrunt** is a thin wrapper around Terraform by Gruntwork that enforces DRY configuration. Instead of copying `.tf` files, you write a `terragrunt.hcl` in each environment that only specifies what **differs** between environments:

```
Without Terragrunt                        With Terragrunt
──────────────────────────────────        ───────────────────────────────────────────
dev/
  main.tf          ← module call          terragrunt-root/
  versions.tf      ← identical              terragrunt.hcl     ← shared: provider, backend
  providers.tf     ← identical              dev/
  terraform.tfvars ← env-specific            terragrunt.hcl   ← only: inputs = { replicas=1 }
staging/                                   prod/
  main.tf          ← copy of dev             terragrunt.hcl   ← only: inputs = { replicas=3 }
  versions.tf      ← copy
  providers.tf     ← copy
  terraform.tfvars ← env-specific
prod/
  (same again)
```

Key Terragrunt ideas:

| Concept | Meaning |
|---------|---------|
| `source` | Points to a Terraform module directory — no `.tf` duplication |
| `find_in_parent_folders()` | Walks up to find the root `terragrunt.hcl` — inherits shared config |
| `inputs = {}` | Passed as `-var` flags to Terraform — replaces `terraform.tfvars` |
| `run-all apply` | Applies every unit in the stack; respects `dependency {}` ordering |
| `dependency {}` | Cross-unit output reference — like a `data` source across state files |
| `.terragrunt-cache` | Terragrunt copies source module here — one isolated copy per unit |
| State isolation | Every unit has its own state — dev and prod never share state |

---

## Part 1 — Terratest

### Concept

Terratest is a Go testing library that:
- Calls `terraform.InitAndApply()` to deploy your real infra
- Lets you assert against live resources via provider-specific helpers
- Calls `terraform.Destroy()` in a `defer` so cleanup always runs even on test failure

```
go test ./...
  └─ TestKindK8sLab057
       ├─ terraform.InitAndApply()          → kind cluster + k8s resources created
       ├─ k8s.GetNamespace()                → assert namespace exists
       ├─ k8s.ListPods()                    → assert 2 pods Running
       ├─ k8s.GetService()                  → assert ClusterIP service exists
       └─ defer terraform.Destroy()         → always runs — no orphaned resources
```

### 1.1 — Project Layout

```
terraform-kind-057-demo/          ← existing lab 057 project (the module under test)
│
test/
├── go.mod
├── go.sum
└── kind_k8s_test.go              ← Terratest file you will create
```

```bash
mkdir -p ~/terraform-kind-057-demo/test
cd ~/terraform-kind-057-demo/test
```

### 1.2 — Initialise the Go Module

```bash
go mod init github.com/saravanans/kind-k8s-057-test
go get github.com/gruntwork-io/terratest/modules/terraform
go get github.com/gruntwork-io/terratest/modules/k8s
go get github.com/gruntwork-io/terratest/modules/logger
go get github.com/stretchr/testify/assert
go mod tidy
```

Expected after `go mod tidy`:
```
go: downloading github.com/gruntwork-io/terratest v0.46.x
go: downloading github.com/stretchr/testify v1.x.x
```

### 1.3 — Write the Test: `test/kind_k8s_test.go`

```go
package test

import (
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestKindK8sLab057(t *testing.T) {
	t.Parallel()

	// ── Point Terraform at the lab-057 root module ──────────────────────────
	tfOpts := &terraform.Options{
		TerraformDir: "../",             // ~/terraform-kind-057-demo/
		Vars: map[string]interface{}{
			"app_name": "robochef-test", // separate name avoids collision with manual run
			"replicas": 2,
		},
		// Silence verbose Terraform output in test logs
		Logger: logger.Discard,
	}

	// Destroy is always deferred — runs even if the test panics
	defer terraform.Destroy(t, tfOpts)

	// ── Apply ───────────────────────────────────────────────────────────────
	terraform.InitAndApply(t, tfOpts)

	// ── Read outputs ────────────────────────────────────────────────────────
	namespace      := terraform.Output(t, tfOpts, "namespace")
	deploymentName := terraform.Output(t, tfOpts, "deployment_name")
	serviceName    := terraform.Output(t, tfOpts, "service_name")

	assert.Equal(t, "robochef-test", namespace)
	assert.Equal(t, "robochef-test-deployment", deploymentName)
	assert.Equal(t, "robochef-test-service", serviceName)

	// ── kubectl options — reuse the kind context set by lab 057 ─────────────
	kubectlOpts := k8s.NewKubectlOptions(
		"kind-terraform-kind-lab",  // context name (set by kind automatically)
		"",                         // kubeconfig path — empty = ~/.kube/config
		namespace,
	)

	// ── Assert namespace exists ─────────────────────────────────────────────
	ns := k8s.GetNamespace(t, kubectlOpts, namespace)
	assert.Equal(t, namespace, ns.Name)

	// ── Wait for pods to reach Running state (up to 3 minutes) ─────────────
	k8s.WaitUntilNumPodsCreated(
		t, kubectlOpts,
		metav1.ListOptions{LabelSelector: "app=robochef-test"},
		2,               // expected pod count
		30,              // retries
		6*time.Second,   // sleep between retries (30 × 6s = 3 min max)
	)

	pods := k8s.ListPods(
		t, kubectlOpts,
		metav1.ListOptions{LabelSelector: "app=robochef-test"},
	)

	assert.Equal(t, 2, len(pods), "expected 2 Running pods")
	for _, pod := range pods {
		k8s.WaitUntilPodAvailable(t, kubectlOpts, pod.Name, 30, 6*time.Second)
	}

	// ── Assert Service exists and is ClusterIP ──────────────────────────────
	svc := k8s.GetService(t, kubectlOpts, serviceName)
	assert.Equal(t, "ClusterIP", string(svc.Spec.Type))
	assert.Equal(t, int32(80), svc.Spec.Ports[0].Port)

	// ── Assert ConfigMap exists ─────────────────────────────────────────────
	cm := k8s.GetConfigMap(t, kubectlOpts, namespace+"-config")
	assert.Equal(t, "saravanans", cm.Data["APP_OWNER"])
	assert.Equal(t, "kind-local",  cm.Data["APP_ENV"])
}
```

### 1.4 — Run the Test

The kind cluster from lab 057 must be running before you start:

```bash
kind get clusters
# terraform-kind-lab   ← must be present
```

If it is not running, recreate it:

```bash
kind create cluster --name terraform-kind-lab --wait 60s
```

Now run the test:

```bash
cd ~/terraform-kind-057-demo/test
go test -v -run TestKindK8sLab057 -timeout 10m
```

Expected output:
```
=== RUN   TestKindK8sLab057
=== PAUSE TestKindK8sLab057
=== CONT  TestKindK8sLab057

    kind_k8s_test.go: Running command terraform with args [init -upgrade=false]
    kind_k8s_test.go: Running command terraform with args [apply -auto-approve -input=false ...]
    kind_k8s_test.go: Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
    kind_k8s_test.go: Waiting for 2 pods to be created...
    kind_k8s_test.go: Pod robochef-test-deployment-xxxxx-aaaaa is now available
    kind_k8s_test.go: Pod robochef-test-deployment-xxxxx-bbbbb is now available
    kind_k8s_test.go: Running command terraform with args [destroy -auto-approve -input=false ...]
    kind_k8s_test.go: Destroy complete! Resources: 4 destroyed.

--- PASS: TestKindK8sLab057 (47.32s)
PASS
ok  	github.com/saravanans/kind-k8s-057-test	47.322s
```

### 1.5 — What Each Assertion Validates

| Assertion | Why it matters |
|-----------|----------------|
| `terraform.Output namespace` == `"robochef-test"` | Terraform applied the correct app_name |
| `k8s.GetNamespace` succeeds | Namespace was actually created in k8s, not just in state |
| `WaitUntilNumPodsCreated` == 2 | Deployment controller created the right replica count |
| `WaitUntilPodAvailable` | Containers started, readiness probe passed |
| `svc.Spec.Type` == `"ClusterIP"` | Service type was not accidentally changed |
| `cm.Data["APP_OWNER"]` == `"saravanans"` | ConfigMap data survived apply unchanged |

---

## Part 2 — Terragrunt

### Concept

Terragrunt wraps Terraform to eliminate repetition when the same module is deployed to multiple environments. Lab 057's kind module is perfect for this — `dev` runs 1 replica, `prod` runs 3.

```
Without Terragrunt                    With Terragrunt
──────────────────────────────        ───────────────────────────────────────
dev/main.tf   ← copy of module call   terragrunt/
dev/versions.tf ← copy               ├── terragrunt.hcl          ← root (shared config)
prod/main.tf  ← copy of module call   ├── dev/
prod/versions.tf ← copy              │   └── terragrunt.hcl      ← only: inputs = {}
                                      └── prod/
                                          └── terragrunt.hcl      ← only: inputs = {}
```

### 2.1 — Install Terragrunt

```bash
# Linux amd64
curl -Lo /tmp/terragrunt \
  https://github.com/gruntwork-io/terragrunt/releases/download/v0.68.0/terragrunt_linux_amd64
chmod +x /tmp/terragrunt
sudo mv /tmp/terragrunt /usr/local/bin/terragrunt
terragrunt --version
# terragrunt version v0.68.0
```

### 2.2 — Project Layout

```
~/terragrunt-kind-061-demo/
├── terragrunt.hcl              ← root: shared generate blocks, provider config
├── dev/
│   └── terragrunt.hcl          ← dev environment inputs
└── prod/
    └── terragrunt.hcl          ← prod environment inputs
```

The **source module** is the existing lab 057 project at `~/terraform-kind-057-demo/`. Terragrunt calls it via a relative `source` path — no need to duplicate any `.tf` files.

```bash
mkdir -p ~/terragrunt-kind-061-demo/dev
mkdir -p ~/terragrunt-kind-061-demo/prod
cd ~/terragrunt-kind-061-demo
```

### 2.3 — Root `terragrunt.hcl`

```hcl
# ~/terragrunt-kind-061-demo/terragrunt.hcl

locals {
  owner   = "saravanans"
  project = "robochef.co"
}

# Shared inputs applied to every child unit
inputs = {
  owner = local.owner
}
```

### 2.4 — `dev/terragrunt.hcl`

```hcl
# ~/terragrunt-kind-061-demo/dev/terragrunt.hcl

terraform {
  # source points at the lab-057 module (the existing project directory)
  source = "../../terraform-kind-057-demo//"
}

# Pull in root-level shared config
include "root" {
  path = find_in_parent_folders()
}

inputs = {
  app_name = "robochef-dev"
  replicas = 1
}
```

### 2.5 — `prod/terragrunt.hcl`

```hcl
# ~/terragrunt-kind-061-demo/prod/terragrunt.hcl

terraform {
  source = "../../terraform-kind-057-demo//"
}

include "root" {
  path = find_in_parent_folders()
}

inputs = {
  app_name = "robochef-prod"
  replicas = 3
}
```

### 2.6 — Apply a Single Environment

```bash
cd ~/terragrunt-kind-061-demo/dev
terragrunt apply --auto-approve
```

Expected:
```
[terragrunt] Copying files from ../../terraform-kind-057-demo into /tmp/.terragrunt-cache/...
[terragrunt] Running command: terraform apply -auto-approve

kubernetes_namespace.app: Creating...
kubernetes_namespace.app: Creation complete after 0s [id=robochef-dev]
kubernetes_config_map.app: Creating...
kubernetes_service.app: Creating...
kubernetes_config_map.app: Creation complete after 0s [id=robochef-dev/robochef-dev-config]
kubernetes_service.app: Creation complete after 0s [id=robochef-dev/robochef-dev-service]
kubernetes_deployment.app: Creating...
kubernetes_deployment.app: Creation complete after 14s [id=robochef-dev/robochef-dev-deployment]

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:
deployment_name = "robochef-dev-deployment"
namespace       = "robochef-dev"
replicas        = "1"
service_name    = "robochef-dev-service"
```

```bash
kubectl get pods -n robochef-dev --context kind-terraform-kind-lab
# NAME                                          READY   STATUS    RESTARTS   AGE
# robochef-dev-deployment-xxxxxxxxx-zzzzz        1/1     Running   0          20s
```

### 2.7 — Apply All Environments at Once

```bash
cd ~/terragrunt-kind-061-demo
terragrunt run-all apply --auto-approve
```

Expected:
```
[terragrunt] Stack at /home/saravanans/terragrunt-kind-061-demo:
  => Module dev  (running)
  => Module prod (running)

[terragrunt] [dev]  Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
[terragrunt] [prod] Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
```

```bash
kubectl get namespaces | grep robochef
# robochef-dev    Active   30s
# robochef-prod   Active   28s

kubectl get pods -n robochef-dev  --context kind-terraform-kind-lab
# 1 pod

kubectl get pods -n robochef-prod --context kind-terraform-kind-lab
# 3 pods
```

### 2.8 — Check State Isolation

Each Terragrunt unit has its own `.terragrunt-cache/<hash>/terraform.tfstate`. The dev and prod states are completely independent:

```bash
# See the cache tree
find ~/terragrunt-kind-061-demo -name "terraform.tfstate" 2>/dev/null
# .../dev/.terragrunt-cache/.../terraform.tfstate
# .../prod/.terragrunt-cache/.../terraform.tfstate
```

### 2.9 — Override Replicas at Runtime

```bash
cd ~/terragrunt-kind-061-demo/prod
terragrunt apply --auto-approve --terragrunt-source-update \
  -var="replicas=5"

kubectl get pods -n robochef-prod --context kind-terraform-kind-lab
# 5 pods now running
```

### 2.10 — Destroy All Environments

```bash
cd ~/terragrunt-kind-061-demo
terragrunt run-all destroy --auto-approve
```

```
[terragrunt] [prod] Destroy complete! Resources: 4 destroyed.
[terragrunt] [dev]  Destroy complete! Resources: 4 destroyed.
```

Terragrunt respects destroy order — `prod` is destroyed before `dev` if there were `dependency {}` blocks.

---

## Part 3 — Terragrunt `dependency {}` Block (Bonus)

If `prod` needed an output from `dev` (e.g., a shared config value), you would add a `dependency` block. This is the Terragrunt equivalent of a Terraform `data` source across state files:

```hcl
# prod/terragrunt.hcl — bonus example (not needed for this lab but shows the pattern)

dependency "dev" {
  config_path = "../dev"

  # Returned if the dev state doesn't exist yet (prevents failure during plan)
  mock_outputs = {
    namespace = "robochef-dev-mock"
  }
}

inputs = {
  app_name       = "robochef-prod"
  replicas       = 3
  dev_namespace  = dependency.dev.outputs.namespace   # cross-unit reference
}
```

```bash
# run-all respects dependency order automatically
terragrunt run-all apply --auto-approve
# dev is applied first, prod second
```

---

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| **Terratest `terraform.Options`** | Struct that specifies `TerraformDir`, `Vars`, and logging — passed to every Terraform helper |
| **`defer terraform.Destroy()`** | Guarantees cleanup runs even if the test panics or fails — never orphan resources |
| **`k8s.WaitUntilPodAvailable`** | Polls until pod is Ready — essential because pods start asynchronously after apply |
| **`k8s.GetConfigMap`** | Reads the live ConfigMap from the cluster and lets you assert on key-value data |
| **Terragrunt `source`** | Points to a Terraform module directory; `//` suffix tells Terragrunt the root of the module |
| **`find_in_parent_folders()`** | Walks up the directory tree to find the root `terragrunt.hcl` — enables DRY config inheritance |
| **`run-all apply`** | Applies every child unit in the stack; respects `dependency {}` ordering |
| **`.terragrunt-cache`** | Terragrunt copies the source module here before running Terraform — one copy per unit |
| **State isolation** | Each Terragrunt unit has its own state file — dev and prod never share state |

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `no such context kind-terraform-kind-lab` | kind cluster not running | `kind create cluster --name terraform-kind-lab --wait 60s` |
| `WaitUntilNumPodsCreated timed out` | Node resource pressure, image pull slow | Increase retry count or pre-pull `nginx:alpine` on the kind node |
| `k8s.GetConfigMap: not found` | ConfigMap name mismatch | Confirm `app_name` var matches the ConfigMap name pattern `${app_name}-config` |
| `find_in_parent_folders: could not find terragrunt.hcl` | Root `terragrunt.hcl` missing | Ensure `~/terragrunt-kind-061-demo/terragrunt.hcl` exists |
| `source module not found` | Relative path wrong | Double-check `../../terraform-kind-057-demo//` resolves to the correct directory |
| `go: module not found` | `go mod tidy` not run | Run `go mod tidy` inside `test/` before `go test` |

---

## Cleanup

```bash
# Destroy Terragrunt environments (if still running)
cd ~/terragrunt-kind-061-demo
terragrunt run-all destroy --auto-approve

# Delete the kind cluster
kind delete cluster --name terraform-kind-lab

# Remove Terragrunt cache
rm -rf ~/terragrunt-kind-061-demo/dev/.terragrunt-cache
rm -rf ~/terragrunt-kind-061-demo/prod/.terragrunt-cache
```

---

## Concept Summary

```
Terratest flow
  go test ./...
    → terraform.InitAndApply()    deploys the real kind k8s resources
    → k8s.GetNamespace()          hits the live cluster API
    → k8s.WaitUntilPodAvailable() polls until pods are Running
    → k8s.GetService()            asserts ClusterIP on port 80
    → defer terraform.Destroy()   always cleans up, even on test failure

Terragrunt flow
  terragrunt-kind-061-demo/
    terragrunt.hcl              shared: owner, project locals
    dev/terragrunt.hcl          source = lab-057 module, replicas = 1
    prod/terragrunt.hcl         source = lab-057 module, replicas = 3

  terragrunt run-all apply      → dev namespace + 1 pod
                                → prod namespace + 3 pods
                                → state files isolated per environment

  dependency {}                 → cross-unit output references
                                → run-all respects apply/destroy order
```
