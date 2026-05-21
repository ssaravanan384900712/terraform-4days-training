# 049 — Terraform Consul State Backend

**By:** Saravanan Sundaramoorthy
**Environment:** Local (Docker required)
**Time:** ~20 minutes

## Topic

Terraform state must live somewhere. The default is a local `terraform.tfstate` file, which breaks the moment two engineers try to apply simultaneously — the second person overwrites the first's state, causing drift, duplicates, or outright failures.

**Remote backends** solve this by storing state on a central server with:
- **Locking** — only one apply runs at a time
- **Durability** — state survives the loss of any individual workstation
- **Visibility** — the whole team reads the same state

**Consul** is a distributed key-value store and service mesh by HashiCorp (the same company that makes Terraform). It was one of the earliest supported Terraform remote backends and is still popular for teams that already run Consul for service discovery or health checking. Its KV store holds state as a JSON blob, and its session-based locking prevents concurrent writes.

This lab runs Consul locally via Docker (no cloud account needed) and stores Terraform state in it.

**Consul backend vs S3+DynamoDB:**

| Feature | Consul backend | S3 + DynamoDB |
|---|---|---|
| Locking | Built-in (sessions) | DynamoDB required separately |
| Setup | Docker run or existing Consul cluster | Two AWS resources to provision |
| Best for | Teams already running Consul | AWS-native teams |
| On-prem | Yes — works without cloud | Needs AWS |
| UI | Built-in at `:8500/ui` | S3 console + DynamoDB console |
| State encryption | Via Consul TLS + ACLs | Via S3 bucket encryption |

---

## What Terraform Creates

```text
random_string.site_id          → 8-character lowercase identifier
local_file.site_config         → /tmp/robochef-consul-demo.txt
```

State is stored in Consul at path `tf/robochef-state` instead of a local file.

---

## Prerequisites

Verify Docker is running:

```bash
docker info | grep "Server Version"
```

---

## File Layout

```text
049-consul-backend/
├── docker-compose.yml
└── main.tf
```

---

## Step 1 — Create the Working Directory

```bash
mkdir -p ~/terraform-labs/049-consul-backend
cd ~/terraform-labs/049-consul-backend
```

---

## Step 2 — docker-compose.yml

```yaml
version: '2'
services:
  consul:
    image: bitnami/consul:1
    ports:
      - '8300:8300'
      - '8301:8301'
      - '8301:8301/udp'
      - '8500:8500'
      - '8600:8600'
      - '8600:8600/udp'
```

**Port reference:**

| Port | Protocol | Purpose |
|---|---|---|
| 8300 | TCP | RPC — server-to-server communication |
| 8301 | TCP/UDP | LAN gossip — agent health across the cluster |
| 8500 | TCP | HTTP API and web UI (this lab uses this) |
| 8600 | TCP/UDP | DNS interface |

---

## Step 3 — Start Consul

```bash
docker-compose up -d
```

Wait ~5 seconds for Consul to initialise, then verify it elected a leader:

```bash
curl -s http://localhost:8500/v1/status/leader
```

Expected output (an IP:port string with quotes):

```
"172.17.0.2:8300"
```

An empty string (`""`) means the election has not completed yet — wait a few more seconds and retry.

You can also open the Consul UI in a browser: `http://localhost:8500/ui`

---

## Step 4 — main.tf

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
  # Consul backend — stores terraform.tfstate in Consul's KV store.
  # The backend block cannot use variables or locals; values must be literals.
  # ---------------------------------------------------------------------------
  backend "consul" {
    address = "localhost:8500"   # HTTP address of the Consul agent
    scheme  = "http"             # http (dev) or https (production with TLS)
    path    = "tf/robochef-state"  # KV path where state is written
    lock    = true               # Enable session-based locking
    gzip    = false              # Don't compress state (easier to read raw)
  }
}

resource "random_string" "site_id" {
  length  = 8
  upper   = false
  special = false
}

resource "local_file" "site_config" {
  filename = "/tmp/robochef-consul-demo.txt"
  content  = "site=robochef.co\nowner=saravanans\nid=${random_string.site_id.result}\n"
}

output "site_id" {
  description = "Random site identifier stored in Consul-backed state"
  value       = random_string.site_id.result
}

output "config_file" {
  description = "Path of the generated config file"
  value       = local_file.site_config.filename
}
```

**Backend block rules:**
- Values must be literals — no `var.`, no `local.`, no interpolation
- Credentials (tokens) can also be passed via environment variables or a `.terraformrc` file to avoid hardcoding

---

## Step 5 — Init with -reconfigure

```bash
terraform init -reconfigure
```

The `-reconfigure` flag tells Terraform to configure this backend from scratch, ignoring any cached backend state from a previous run. This is safe when you are starting fresh or switching backends.

**-reconfigure vs -migrate-state:**

| Flag | When to use |
|---|---|
| `-reconfigure` | Starting fresh; discard old local state (or it doesn't exist) |
| `-migrate-state` | Switching from local to remote; copies existing local state into the new backend |

Expected output:

```
Initializing the backend...

Successfully configured the backend "consul"! Terraform will automatically
use this backend unless the backend configuration changes.

Initializing provider plugins...
...
Terraform has been successfully initialized!
```

Notice that Terraform does **not** create a local `terraform.tfstate` file. All state goes to Consul.

---

## Step 6 — Apply

```bash
terraform apply -auto-approve
```

Sample output:

```
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:
site_id     = "k3np7wzq"
config_file = "/tmp/robochef-consul-demo.txt"
```

Verify the local file was written:

```bash
cat /tmp/robochef-consul-demo.txt
```

```
site=robochef.co
owner=saravanans
id=k3np7wzq
```

---

## Step 7 — Verify State in Consul

```bash
# Fetch raw state from Consul KV (Base64-encoded by default)
curl -s "http://localhost:8500/v1/kv/tf/robochef-state" | python3 -m json.tool
```

The Consul KV API returns a JSON object where the `Value` field is Base64-encoded:

```json
[
    {
        "LockIndex": 0,
        "Key": "tf/robochef-state",
        "Flags": 0,
        "Value": "eyJ2ZXJzaW9uIjo0LCJ0ZXJyYWZvcm1fdmVyc2lvbi...",
        "CreateIndex": 12,
        "ModifyIndex": 18
    }
]
```

To see the actual Terraform state JSON, use the `?raw` query parameter:

```bash
curl -s "http://localhost:8500/v1/kv/tf/robochef-state?raw" | python3 -m json.tool | head -30
```

Sample decoded output:

```json
{
    "version": 4,
    "terraform_version": "1.9.0",
    "serial": 1,
    "lineage": "3f2a1d8e-...",
    "outputs": {
        "config_file": {
            "value": "/tmp/robochef-consul-demo.txt",
            "type": "string"
        },
        "site_id": {
            "value": "k3np7wzq",
            "type": "string"
        }
    },
    "resources": [
        ...
    ]
}
```

This is exactly the same JSON structure as `terraform.tfstate` — just stored in Consul instead of a local file.

**Via the UI:** Open `http://localhost:8500/ui/dc1/kv` in a browser. You will see the `tf/robochef-state` key listed. Click it to view or edit the raw value.

---

## Step 8 — Observe State Locking

Consul uses sessions for locking. When Terraform runs apply, it:
1. Creates a Consul session
2. Acquires a lock on the state key
3. Reads, modifies, and writes state
4. Releases the lock

To observe this, open a second terminal and run `terraform plan` while `terraform apply` is running. Terraform will print:

```
Error: Error locking state: Error acquiring the state lock: Lock Info:
  ID:        3f2a1d8e-...
  Path:      tf/robochef-state
  Operation: OperationTypeApply
  Who:       saravanans@hostname
  ...
```

This prevents two engineers from applying simultaneously and corrupting shared state.

---

## Step 9 — Update and Re-apply

Modify the local file content directly in main.tf to observe a state update cycle:

```hcl
resource "local_file" "site_config" {
  filename = "/tmp/robochef-consul-demo.txt"
  content  = "site=robochef.co\nowner=saravanans\nid=${random_string.site_id.result}\nupdated=true\n"
}
```

Apply the change:

```bash
terraform apply -auto-approve
```

Re-read the state from Consul:

```bash
curl -s "http://localhost:8500/v1/kv/tf/robochef-state?raw" | python3 -m json.tool | grep serial
```

The `serial` field increments with each state write — Consul preserves the latest version.

---

## Key Concepts

### Consul KV path structure

The `path` in the backend block maps to a key in Consul's KV store. Good practice:

```
tf/<workspace>/<project-name>
tf/default/robochef-state
tf/staging/robochef-state
tf/production/robochef-state
```

Each Terraform workspace maps to a separate KV key, so teams can share one Consul cluster across environments without state collisions.

### ACL tokens for production

In production, Consul runs with ACLs enabled. Pass the token:

```hcl
backend "consul" {
  address      = "consul.internal:8500"
  scheme       = "https"
  path         = "tf/production/robochef-state"
  lock         = true
  access_token = ""   # leave empty; set CONSUL_HTTP_TOKEN env var instead
}
```

```bash
export CONSUL_HTTP_TOKEN="<your-token>"
terraform init
```

### gzip = true

Enabling `gzip = true` compresses the state blob before writing to Consul. This reduces KV storage size for large state files but makes the raw KV value unreadable without decompression. For learning and debugging, keep it `false`.

---

## Destroy

```bash
terraform destroy -auto-approve
rm -rf .terraform
```

Verify the state key is now empty (or the resources array is empty):

```bash
curl -s "http://localhost:8500/v1/kv/tf/robochef-state?raw" | python3 -m json.tool | grep '"resources"'
```

Stop Consul:

```bash
docker-compose down
```

Verify the container is gone:

```bash
docker ps | grep consul
```

---

## Summary

| Concept | Detail |
|---|---|
| Consul backend type | `backend "consul" {}` |
| State storage | Consul KV store, path specified by `path = "..."` |
| Locking | Session-based; set `lock = true` (default) |
| State API | `GET /v1/kv/<path>?raw` returns raw JSON state |
| ACL auth | Set `CONSUL_HTTP_TOKEN` env var in production |
| Best for | Teams already running Consul; on-prem; no cloud needed |
| vs S3+DynamoDB | Simpler for AWS teams; Consul is better on-prem |

Consul backend is a solid choice for teams that already operate a Consul cluster — zero additional infrastructure required, built-in locking, and a clean UI for state inspection.
