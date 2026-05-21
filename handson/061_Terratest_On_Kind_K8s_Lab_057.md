# Lab 061 — Terratest Applied to the kind Kubernetes Lab (057)

**By: Saravanan Sundaramoorthy**
**Environment:** Ubuntu Linux — requires kind v0.23.0, kubectl, Go 1.21+, Terraform ≥ 1.3
**Prerequisites:** Lab 057 completed — `~/terraform-kind-057-demo/` must exist
**Time:** ~25 minutes

---

## What You'll Learn

| Topic | Concept |
|-------|---------|
| Terratest | Write Go integration tests that call `terraform apply` and assert against live infrastructure |
| `k8s` Terratest module | Use `k8s.GetNamespace`, `k8s.ListPods`, `k8s.GetService`, `k8s.GetConfigMap` |
| `defer terraform.Destroy` | Guarantee cleanup even when a test panics or fails mid-run |
| `t.Parallel()` | Run multiple test environments simultaneously in Go |
| Live assertions | Difference between state-based checks and real cluster API checks |

---

## Introduction to Terratest

Terraform configs are code — and code needs tests. The problem with Terraform is that `terraform validate` and even `terraform plan` cannot tell you whether your infrastructure actually **works**: whether the pods come up, whether the service routes traffic, whether the ConfigMap keys are correct.

**Terratest** is a Go library by Gruntwork that solves this. It performs real integration tests by:

1. Calling `terraform apply` against real providers (AWS, Kubernetes, local, etc.)
2. Letting you write assertions against live infrastructure using provider-specific helper modules (`k8s`, `aws`, `http`, etc.)
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

Why Go? First-class concurrency (`t.Parallel()` runs many environments simultaneously), a fast compiler, and Gruntwork's `terratest` package covers every major Terraform provider.

| Terratest concept | Meaning |
|-------------------|---------|
| `terraform.Options` | Struct: TerraformDir, Vars, EnvVars, Logger — one per test |
| `terraform.InitAndApply` | Runs `terraform init` then `terraform apply --auto-approve` |
| `terraform.Output` | Reads a named output from the applied state |
| `terraform.Destroy` | Runs `terraform destroy --auto-approve` — always deferred |
| `k8s.NewKubectlOptions` | Creates kubectl context: cluster name, kubeconfig path, namespace |
| `k8s.WaitUntilPodAvailable` | Polls with retries until pod status = Ready |
| `k8s.GetService` | Fetches the live Service object for assertion |
| `k8s.GetConfigMap` | Fetches the live ConfigMap — assert on `.Data["key"]` |

---

## Project Layout

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

---

## Step 1 — Initialise the Go Module

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

---

## Step 2 — Write the Test: `test/kind_k8s_test.go`

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

---

## Step 3 — Run the Test

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

---

## What Each Assertion Validates

| Assertion | Why it matters |
|-----------|----------------|
| `terraform.Output namespace` == `"robochef-test"` | Terraform applied the correct `app_name` |
| `k8s.GetNamespace` succeeds | Namespace actually exists in k8s, not just in Terraform state |
| `WaitUntilNumPodsCreated` == 2 | Deployment controller created the correct replica count |
| `WaitUntilPodAvailable` | Container started and readiness probe passed |
| `svc.Spec.Type` == `"ClusterIP"` | Service type was not accidentally changed |
| `cm.Data["APP_OWNER"]` == `"saravanans"` | ConfigMap data survived apply unchanged |

---

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| **`terraform.Options`** | Struct that specifies `TerraformDir`, `Vars`, and logging — passed to every Terraform helper |
| **`defer terraform.Destroy()`** | Guarantees cleanup runs even if the test panics or fails — never orphan resources |
| **`k8s.WaitUntilPodAvailable`** | Polls until pod is Ready — essential because pods start asynchronously after apply |
| **`k8s.GetConfigMap`** | Reads the live ConfigMap from the cluster — assert on `.Data["key"]` values |
| **`t.Parallel()`** | Multiple tests run simultaneously — each needs a unique `app_name` to avoid resource collision |
| **`logger.Discard`** | Suppresses Terraform CLI output in test logs — use `logger.Default` when debugging |

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `no such context kind-terraform-kind-lab` | kind cluster not running | `kind create cluster --name terraform-kind-lab --wait 60s` |
| `WaitUntilNumPodsCreated timed out` | Node resource pressure or slow image pull | Increase retry count or pre-pull `nginx:alpine` on the kind node |
| `k8s.GetConfigMap: not found` | ConfigMap name mismatch | Confirm `app_name` var matches the pattern `${app_name}-config` in `main.tf` |
| `go: module not found` | `go mod tidy` not run | Run `go mod tidy` inside `test/` before `go test` |
| Test passes but leaves resources | `defer` placed after `InitAndApply` | Always `defer terraform.Destroy` immediately after defining `tfOpts`, before `InitAndApply` |

---

## Cleanup

Terratest runs `terraform destroy` automatically via `defer`. If a test is interrupted mid-run:

```bash
cd ~/terraform-kind-057-demo
terraform destroy --auto-approve
```

Then delete the kind cluster when finished:

```bash
kind delete cluster --name terraform-kind-lab
```

---

## Concept Summary

```
go test ./...
  └─ TestKindK8sLab057
       ├─ terraform.Options { TerraformDir="../", Vars: {app_name, replicas} }
       ├─ defer terraform.Destroy()          ← registered first, runs last
       ├─ terraform.InitAndApply()           ← deploys 4 k8s resources via kind
       ├─ terraform.Output("namespace")      ← reads from Terraform state
       ├─ k8s.GetNamespace()                 ← hits live cluster API
       ├─ k8s.WaitUntilNumPodsCreated(2)     ← polls until 2 pods exist
       ├─ k8s.WaitUntilPodAvailable()        ← polls until pod is Ready
       ├─ k8s.GetService()                   ← asserts ClusterIP on port 80
       └─ k8s.GetConfigMap()                 ← asserts APP_OWNER = saravanans
```
