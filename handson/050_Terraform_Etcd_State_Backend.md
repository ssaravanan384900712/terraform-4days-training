# 050 — Terraform etcd State Backend

**By:** Saravanan Sundaramoorthy
**Environment:** Local (Docker required)
**Time:** ~20 minutes

## Topic

**etcd** is a strongly-consistent, distributed key-value store written in Go. If you have used Kubernetes, you have already relied on etcd — it is the primary datastore for all Kubernetes cluster state: pod specs, secrets, config maps, service definitions, and everything else the control plane needs to function.

Because etcd is already part of every Kubernetes cluster, it is a natural choice for a Terraform remote state backend when you work in Kubernetes-centric environments. The Terraform `etcdv3` backend stores state in etcd under a configurable key prefix, with optional distributed locking.

**etcd vs Consul — when to choose which:**

| Feature | etcd (etcdv3 backend) | Consul backend |
|---|---|---|
| Primary role | Kubernetes control plane store | Service mesh + KV store |
| Best for | K8s-native teams, already have etcd | Teams using Consul for service discovery |
| Locking | Yes (`lock = true`) | Yes (session-based) |
| Historical reads | Yes — revision-based snapshots | No built-in history |
| UI | None built-in (use `etcdctl`) | Built-in web UI at `:8500/ui` |
| Encryption at rest | Via etcd TLS + encryption config | Via Consul TLS + ACLs |
| On-prem / cloud-neutral | Yes | Yes |

**etcdv3 vs etcdv2:** The Terraform backend is named `etcdv3` because etcd v3 introduced a completely new gRPC-based API that is not backward-compatible with the original v2 HTTP API. Always use `etcdv3` — the old `etcd` backend type (v2) is deprecated and removed in recent Terraform versions.

This lab runs etcd locally via Docker and walks through `etcdctl` commands alongside Terraform.

---

## What Terraform Creates

```text
random_string.deploy_id        → 8-character lowercase deployment identifier
local_file.deploy_config       → /tmp/robochef-etcd-demo.txt
```

State is stored in etcd under prefix `terraform-state/`.

---

## Prerequisites

Verify Docker is running:

```bash
docker info | grep "Server Version"
```

---

## File Layout

```text
050-etcd-backend/
└── main.tf
```

---

## Step 1 — Create the Working Directory

```bash
mkdir -p ~/terraform-labs/050-etcd-backend
cd ~/terraform-labs/050-etcd-backend
```

---

## Step 2 — Start etcd with Docker

```bash
docker run -d --name etcd-server --rm \
    --publish 2379:2379 \
    --publish 2380:2380 \
    --env ALLOW_NONE_AUTHENTICATION=yes \
    --env ETCD_ADVERTISE_CLIENT_URLS=http://etcd-server:2379 \
    bitnami/etcd:latest
```

**Flag reference:**

| Flag | Purpose |
|---|---|
| `--name etcd-server` | Container name (used internally by etcd) |
| `--rm` | Auto-remove the container when it stops |
| `--publish 2379:2379` | Client API port (gRPC — used by `etcdctl` and Terraform) |
| `--publish 2380:2380` | Peer port (cluster member communication) |
| `ALLOW_NONE_AUTHENTICATION=yes` | Skip authentication (dev only — never in production) |
| `ETCD_ADVERTISE_CLIENT_URLS` | URL that clients should use to reach this etcd node |

Verify the container is running:

```bash
docker ps | grep etcd
```

---

## Step 3 — Install etcdctl

`etcdctl` is the CLI client for etcd. It is separate from the etcd server binary.

```bash
sudo apt-get install -y etcd-client
```

Verify the installation:

```bash
etcdctl version
```

**Critical: Set the API version to v3**

```bash
export ETCDCTL_API=3
```

Without this, `etcdctl` defaults to the v2 API and all commands will fail or return unexpected results. Set this in every terminal session where you use `etcdctl`.

---

## Step 4 — Explore etcd with etcdctl

Before running Terraform, spend a moment exploring etcd directly. This makes it much easier to understand what Terraform is doing when it stores state.

**Basic put and get:**

```bash
export ETCDCTL_API=3

etcdctl put foo bar
# OK

etcdctl get foo
# foo
# bar
```

**Historical reads — one of etcd's most powerful features:**

etcd stores every write as a new revision. You can read any past revision at any time.

```bash
etcdctl put foo bar1
# OK   (revision 2)

etcdctl put foo bar2
# OK   (revision 3)

etcdctl put foo bar3
# OK   (revision 4)

# Read the current value
etcdctl get foo
# foo
# bar3

# Read the value at revision 2
etcdctl get foo --rev=2
# foo
# bar1

# Read the value at revision 3
etcdctl get foo --rev=3
# foo
# bar2
```

This revision-based history is why Kubernetes uses etcd — it can replay or audit any change to cluster state. For Terraform state, each apply increments a Terraform internal serial number, but etcd also tracks its own revision history independently.

**List all keys:**

```bash
etcdctl get --prefix ""
# Shows all keys in etcd
```

**Delete a key:**

```bash
etcdctl del foo
# 1 (number of keys deleted)
```

**Watch for changes (in a separate terminal):**

```bash
export ETCDCTL_API=3
etcdctl watch foo
# Blocks and prints changes as they happen
```

---

## Step 5 — main.tf

```hcl
terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }

  # ---------------------------------------------------------------------------
  # etcdv3 backend — stores terraform.tfstate in etcd under the given prefix.
  # Note: the backend type is "etcdv3", NOT "etcd" (v2 is deprecated).
  # ---------------------------------------------------------------------------
  backend "etcdv3" {
    endpoints = ["localhost:2379"]  # etcd client endpoint(s)
    lock      = true                # Enable distributed locking
    prefix    = "terraform-state/"  # Key prefix in etcd KV store
  }
}

resource "random_string" "deploy_id" {
  length  = 8
  upper   = false
  special = false
}

resource "local_file" "deploy_config" {
  filename = "/tmp/robochef-etcd-demo.txt"
  content  = "site=robochef.co\nowner=saravanans\ndeploy_id=${random_string.deploy_id.result}\n"
}

output "deploy_id" {
  description = "Random deployment ID stored in etcd-backed state"
  value       = random_string.deploy_id.result
}

output "config_file" {
  description = "Path of the generated config file"
  value       = local_file.deploy_config.filename
}
```

**Backend block notes:**
- `endpoints` is a list — you can pass multiple etcd nodes for high availability: `["etcd1:2379", "etcd2:2379", "etcd3:2379"]`
- `prefix` acts like a directory: all Terraform state keys are written under `terraform-state/`
- `lock = true` uses etcd leases for distributed locking (same mechanism Kubernetes uses for leader election)

---

## Step 6 — Init

```bash
terraform init
```

Expected output:

```
Initializing the backend...

Successfully configured the backend "etcdv3"! Terraform will automatically
use this backend unless the backend configuration changes.

Initializing provider plugins...
- Finding hashicorp/random versions matching "~> 3.0"...
- Finding hashicorp/local versions matching "~> 2.0"...
...
Terraform has been successfully initialized!
```

No `terraform.tfstate` file is created locally. State lives in etcd.

---

## Step 7 — Apply

```bash
terraform apply -auto-approve
```

Sample output:

```
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:
deploy_id   = "n7xqwpkm"
config_file = "/tmp/robochef-etcd-demo.txt"
```

Read the generated file:

```bash
cat /tmp/robochef-etcd-demo.txt
```

```
site=robochef.co
owner=saravanans
deploy_id=n7xqwpkm
```

---

## Step 8 — Verify State in etcd

```bash
export ETCDCTL_API=3

# List all keys under the terraform-state prefix
etcdctl get --prefix "terraform-state/"
```

You will see the Terraform state JSON printed directly to your terminal. Sample output:

```
terraform-state/
{"version":4,"terraform_version":"1.9.0","serial":1,"lineage":"a3f2d1bc-...","outputs":{"config_file":{"value":"/tmp/robochef-etcd-demo.txt","type":"string"},"deploy_id":{"value":"n7xqwpkm","type":"string"}},"resources":[{"mode":"managed","type":"local_file","name":"deploy_config","provider":"provider[\"registry.terraform.io/hashicorp/local\"]","instances":[{"schema_version":0,"attributes":{"content":"site=robochef.co\nowner=saravanans\ndeploy_id=n7xqwpkm\n","directory_permission":"0777","file_permission":"0777","filename":"/tmp/robochef-etcd-demo.txt","id":"sha1:...","sensitive_content":null,"source":null},"sensitive_attributes":[]}]},{"mode":"managed","type":"random_string","name":"deploy_id","provider":"provider[\"registry.terraform.io/hashicorp/random\"]","instances":[{"schema_version":2,"attributes":{"id":"n7xqwpkm","keepers":null,"length":8,"lower":true,"min_lower":0,"min_numeric":0,"min_special":0,"min_upper":0,"numeric":true,"result":"n7xqwpkm","special":false,"upper":false},"sensitive_attributes":[]}]}],"check_results":null}
```

This is the full Terraform state JSON — the same content you would normally see in a local `terraform.tfstate` file, now stored in etcd.

**Pretty-print the state:**

```bash
etcdctl get --prefix "terraform-state/" | tail -1 | python3 -m json.tool | head -20
```

---

## Step 9 — Update and Observe State Versioning

Modify the file content to trigger a state update. Edit main.tf:

```hcl
resource "local_file" "deploy_config" {
  filename = "/tmp/robochef-etcd-demo.txt"
  content  = "site=robochef.co\nowner=saravanans\ndeploy_id=${random_string.deploy_id.result}\nversion=2\n"
}
```

Apply the change:

```bash
terraform apply -auto-approve
```

Read the state again and check the `serial` field:

```bash
export ETCDCTL_API=3
etcdctl get --prefix "terraform-state/" | tail -1 | python3 -m json.tool | grep serial
```

```json
    "serial": 2,
```

The serial increments with each state write. etcd also maintains its own internal revision number (visible in `etcdctl get --write-out=json`). These are two independent counters: Terraform's `serial` tracks Terraform-level changes, while etcd's revision tracks every write to the KV store (including lock acquisition and release).

**Read the etcd revision for the state key:**

```bash
export ETCDCTL_API=3
etcdctl get "terraform-state/" --write-out=json | python3 -m json.tool | grep -E '"mod_revision|create_revision"'
```

---

## Key Concepts

### Multiple endpoints for HA

In a real Kubernetes environment, etcd runs as a 3-node or 5-node cluster. Pass all endpoints:

```hcl
backend "etcdv3" {
  endpoints = [
    "etcd1.internal:2379",
    "etcd2.internal:2379",
    "etcd3.internal:2379",
  ]
  lock   = true
  prefix = "terraform-state/"
}
```

Terraform connects to whichever node is available. etcd's Raft consensus ensures all nodes agree on state.

### TLS in production

Never use `ALLOW_NONE_AUTHENTICATION=yes` outside of a local lab. Production etcd requires mTLS:

```hcl
backend "etcdv3" {
  endpoints  = ["etcd.internal:2379"]
  lock       = true
  prefix     = "terraform-state/robochef/"
  cacert_pem = "/etc/ssl/etcd/ca.pem"
  cert_pem   = "/etc/ssl/etcd/client.pem"
  key_pem    = "/etc/ssl/etcd/client-key.pem"
}
```

### Prefix naming convention

Good prefix design separates environments and projects:

```
terraform-state/robochef/production/
terraform-state/robochef/staging/
terraform-state/robochef/development/
```

Multiple Terraform root modules can use the same etcd cluster without collisions as long as their prefixes are unique.

### ETCDCTL_API=3 — why it matters

etcd v2 and v3 have entirely different APIs. The v2 API uses REST over HTTP. The v3 API uses gRPC. When you run `etcdctl` without setting `ETCDCTL_API=3`, older versions default to v2, and commands like `etcdctl get foo` hit the wrong endpoint and return nothing (or an error). Always set this variable.

```bash
# Add to your ~/.bashrc to make it permanent
echo 'export ETCDCTL_API=3' >> ~/.bashrc
source ~/.bashrc
```

### etcd cheat sheet

```bash
export ETCDCTL_API=3

# Write
etcdctl put <key> <value>

# Read
etcdctl get <key>
etcdctl get <key> --rev=<revision>

# List all keys with a prefix
etcdctl get --prefix <prefix>

# Delete
etcdctl del <key>

# Watch for changes
etcdctl watch <key>
etcdctl watch --prefix <prefix>

# Cluster health
etcdctl endpoint health
etcdctl endpoint status

# Show revision metadata
etcdctl get <key> --write-out=json
```

References:
- etcd interacting guide: https://etcd.io/docs/v3.4/dev-guide/interacting_v3/
- etcd cheat sheet: https://lzone.de/cheat-sheet/etcd
- bitnami/etcd Docker image: https://hub.docker.com/r/bitnami/etcd/

---

## Destroy

```bash
terraform destroy -auto-approve
rm -rf .terraform
```

Verify the state key reflects the destroyed resources (resources array should be empty):

```bash
export ETCDCTL_API=3
etcdctl get --prefix "terraform-state/" | tail -1 | python3 -m json.tool | grep '"resources"'
```

Stop and remove the etcd container:

```bash
docker stop etcd-server
```

The container was started with `--rm`, so it removes itself automatically when stopped. Verify:

```bash
docker ps -a | grep etcd
```

---

## Summary

| Concept | Detail |
|---|---|
| Backend type | `backend "etcdv3" {}` (NOT `etcd` — that is the deprecated v2 backend) |
| State storage | etcd KV store under the given `prefix` |
| Locking | etcd lease-based; set `lock = true` |
| ETCDCTL_API | Must set `export ETCDCTL_API=3` for all etcdctl commands |
| Historical reads | `etcdctl get <key> --rev=<n>` reads any past revision |
| HA config | Pass multiple etcd endpoints in the `endpoints` list |
| Best for | K8s-native teams; etcd already running in the cluster |
| vs Consul | etcd = simpler KV; Consul = full service mesh with UI |
| Production | Requires mTLS (`cacert_pem`, `cert_pem`, `key_pem`) |

The etcdv3 backend is the natural choice for Kubernetes platform teams — they already operate etcd as part of the cluster, so Terraform gets a free remote state backend with strong consistency and built-in versioning at no extra infrastructure cost.
