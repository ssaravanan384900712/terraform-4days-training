# 051 — Terraform + HashiCorp Vault Integration

**By:** Saravanan Sundaramoorthy
**Environment:** Local (Vault dev mode, no cloud credentials needed)
**Time:** ~20 minutes

---

## Topic

**HashiCorp Vault** is a secrets management platform that stores, controls access to, and audits tokens, passwords, API keys, and certificates. Terraform's `hashicorp/vault` provider lets you read secrets from Vault at plan/apply time — so credentials never appear in `.tf` files, environment variables, or CI pipelines.

**The core problem Vault solves:**

| Where secrets live today | Risk |
|---|---|
| Hardcoded in `.tf` files | Committed to Git — anyone with repo access can read them |
| Environment variables | Visible in shell history, CI logs, `ps aux` output |
| SSM Parameter Store / Secrets Manager | Cloud-only, no cross-cloud, no dynamic credentials |
| HashiCorp Vault | Encrypted at rest, full audit log, RBAC, dynamic credentials, lease-based rotation |

**How Vault + Terraform work together:**

```
┌─────────────────────────────────────────┐
│  Vault Server (dev mode)                │
│  http://localhost:8200                  │
│  ┌─────────────────────────────┐        │
│  │ secret/robochef-db          │        │
│  │   username: robochef        │        │
│  │   password: ****            │        │
│  │   host: rds.amazonaws.com   │        │
│  └─────────────────────────────┘        │
└──────────────┬──────────────────────────┘
               │ vault_generic_secret
               │ data source
┌──────────────▼──────────────────────────┐
│  Terraform Plan/Apply                   │
│  data "vault_generic_secret"            │
│  → reads secret at plan time            │
│  → uses value in resource config        │
│  → output marked sensitive = true       │
└─────────────────────────────────────────┘
```

**Comparison: secret management options**

| Method | Security | Auditability | Rotation |
|---|---|---|---|
| Hardcode in .tf | Very Bad | None | Manual |
| Environment vars | OK | None | Manual |
| AWS Secrets Manager (lab 032) | Good | CloudTrail | Semi-auto |
| HashiCorp Vault | Excellent | Full audit log | Fully auto |

---

## What Terraform Creates

```text
data.vault_generic_secret.robochef_db     → Reads robochef DB credentials from Vault
data.vault_generic_secret.chillbot_api    → Reads chillbot API key from Vault
local_file.app_config                     → /tmp/robochef-app-config.txt (mode 0600)
local_file.chillbot_config                → /tmp/chillbot-api-config.txt (mode 0600)
```

No cloud resources are created — this lab is entirely local.

---

## File Layout

```text
terraform-vault-051-demo/
├── providers.tf
├── main.tf
└── outputs.tf
```

---

## Step 1 — Install Vault Binary

Open a terminal and run:

```bash
sudo apt update
sudo apt install -y wget zip unzip jq tree

# Download Vault
wget https://releases.hashicorp.com/vault/1.15.0/vault_1.15.0_linux_amd64.zip
unzip vault_1.15.0_linux_amd64.zip
sudo mv vault /usr/local/bin/
vault version
```

Expected:

```
Vault v1.15.0 (...)
```

---

## Step 2 — Start Vault in Dev Mode (Terminal 1)

Open a **new terminal tab** (Terminal 1) and run:

```bash
vault server -dev -dev-root-token-id="environment"
```

Expected output includes:

```
==> Vault server configuration:

             Api Address: http://127.0.0.1:8200
                     Cgo: disabled
         Cluster Address: https://127.0.0.1:8201
              Go Version: go1.21.3
              Listener 1: tcp (addr: "127.0.0.1:8200", cluster address: "127.0.0.1:8201", max_request_duration: "1m30s", max_request_size: "33554432", tls: "disabled")
               Log Level: info
                   Mlock: supported: true, enabled: false
           Recovery Mode: false
                 Storage: inmem
                 Version: Vault v1.15.0

==> Vault server started! Log data will stream in below:

WARNING! dev mode is enabled! In this mode, Vault runs entirely in-memory
and starts unsealed with a single unseal key. The root token is simply
for logging in. All data is lost! Do NOT use dev mode in production installations!

Root Token: environment
```

> **Note:** Dev mode = in-memory storage, auto-unsealed, no persistence. Data is lost when the server stops. Never use for production.

**Leave Terminal 1 running.** All remaining steps use Terminal 2.

---

## Step 3 — Configure Vault CLI (Terminal 2)

Open Terminal 2 and export the Vault address and token:

```bash
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="environment"

vault status
```

Expected:

```
Key             Value
---             -----
Seal Type       shamir
Initialized     true
Sealed          false
Total Shares    1
Threshold       1
Version         Vault v1.15.0
Storage Type    inmem
...
```

`Sealed: false` confirms Vault is ready.

---

## Step 4 — Store Secrets in Vault

```bash
# Store database credentials for robochef.co
vault kv put secret/robochef-db \
  username="robochef" \
  password="RobochefDB2024!" \
  host="robochef-rds.ap-south-1.rds.amazonaws.com"

# Store API key for chillbotindia.com
vault kv put secret/chillbot-api \
  api_key="chillbot-api-key-xyz" \
  region="ap-south-1"
```

Read them back to confirm:

```bash
vault kv get secret/robochef-db
```

Expected:

```
======= Secret Path =======
secret/data/robochef-db

======= Metadata =======
Key              Value
---              -----
created_time     2024-01-15T10:00:00.000000000Z
version          1

====== Data ======
Key         Value
---         -----
host        robochef-rds.ap-south-1.rds.amazonaws.com
password    RobochefDB2024!
username    robochef
```

Read a single field:

```bash
vault kv get -field=password secret/robochef-db
```

Expected:

```
RobochefDB2024!
```

---

## Step 5 — Create Terraform Project

```bash
mkdir -p ~/terraform-vault-051-demo
cd ~/terraform-vault-051-demo
```

### providers.tf

```bash
cat > ~/terraform-vault-051-demo/providers.tf <<'EOF_TF'
terraform {
  required_providers {
    vault = { source = "hashicorp/vault", version = "~> 3.0" }
    local = { source = "hashicorp/local", version = "~> 2.0" }
  }
}

provider "vault" {
  address = "http://127.0.0.1:8200"
  token   = "environment"  # in prod: use VAULT_TOKEN env var instead
}
EOF_TF
```

### main.tf

```bash
cat > ~/terraform-vault-051-demo/main.tf <<'EOF_TF'
# Read robochef DB credentials from Vault
data "vault_generic_secret" "robochef_db" {
  path = "secret/robochef-db"
}

# Read chillbot API key from Vault
data "vault_generic_secret" "chillbot_api" {
  path = "secret/chillbot-api"
}

# Use the secrets to generate a config file (simulating app deployment)
resource "local_file" "app_config" {
  filename        = "/tmp/robochef-app-config.txt"
  file_permission = "0600"
  content = <<-EOT
    # robochef.co application config
    # Generated by Terraform + Vault
    db_host=${data.vault_generic_secret.robochef_db.data["host"]}
    db_user=${data.vault_generic_secret.robochef_db.data["username"]}
    # password is NOT written to this file in plaintext
  EOT
}

resource "local_file" "chillbot_config" {
  filename        = "/tmp/chillbot-api-config.txt"
  file_permission = "0600"
  content = "region=${data.vault_generic_secret.chillbot_api.data["region"]}\n"
}
EOF_TF
```

### outputs.tf

```bash
cat > ~/terraform-vault-051-demo/outputs.tf <<'EOF_TF'
output "robochef_db_host" {
  value = data.vault_generic_secret.robochef_db.data["host"]
  # NOT sensitive — just the host
}

output "robochef_db_username" {
  value = data.vault_generic_secret.robochef_db.data["username"]
}

output "robochef_db_password" {
  sensitive = true   # REQUIRED for sensitive values
  value     = data.vault_generic_secret.robochef_db.data["password"]
}

output "config_files" {
  value = [local_file.app_config.filename, local_file.chillbot_config.filename]
}
EOF_TF
```

Verify the layout:

```bash
tree ~/terraform-vault-051-demo
```

Expected:

```
/home/<user>/terraform-vault-051-demo
├── main.tf
├── outputs.tf
└── providers.tf
```

---

## Step 6 — Init and Apply

```bash
cd ~/terraform-vault-051-demo
terraform init
terraform apply -auto-approve
```

Expected output:

```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/vault versions matching "~> 3.0"...
- Finding hashicorp/local versions matching "~> 2.0"...
- Installing hashicorp/vault v3.x.x...
- Installing hashicorp/local v2.x.x...

data.vault_generic_secret.robochef_db: Reading...
data.vault_generic_secret.chillbot_api: Reading...
data.vault_generic_secret.robochef_db: Read complete after 0s [id=secret/robochef-db]
data.vault_generic_secret.chillbot_api: Read complete after 0s [id=secret/chillbot-api]

Terraform used the selected providers to generate the following execution plan.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # local_file.app_config will be created
  + resource "local_file" "app_config" {
      + content              = <<-EOT
            # robochef.co application config
            # Generated by Terraform + Vault
            db_host=robochef-rds.ap-south-1.rds.amazonaws.com
            db_user=robochef
            # password is NOT written to this file in plaintext
        EOT
      + filename             = "/tmp/robochef-app-config.txt"
      + file_permission      = "0600"
      ...
    }

  # local_file.chillbot_config will be created
  + resource "local_file" "chillbot_config" {
      + content         = "region=ap-south-1\n"
      + filename        = "/tmp/chillbot-api-config.txt"
      + file_permission = "0600"
      ...
    }

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

config_files = [
  "/tmp/robochef-app-config.txt",
  "/tmp/chillbot-api-config.txt",
]
robochef_db_host = "robochef-rds.ap-south-1.rds.amazonaws.com"
robochef_db_username = "robochef"
robochef_db_password = <sensitive>
```

> **Key observation:** `robochef_db_password = <sensitive>` — Terraform never prints the actual value to the terminal. The password exists only inside the Vault and in Terraform's in-memory state during apply.

Inspect the generated config file:

```bash
cat /tmp/robochef-app-config.txt
```

Expected:

```
# robochef.co application config
# Generated by Terraform + Vault
db_host=robochef-rds.ap-south-1.rds.amazonaws.com
db_user=robochef
# password is NOT written to this file in plaintext
```

The password was intentionally excluded from the config file — this is exactly the pattern you use in real deployments.

---

## Step 7 — Update a Secret and Re-Apply

Update the password directly in Vault — no `.tf` file changes needed:

```bash
vault kv put secret/robochef-db \
  username="robochef" \
  password="NewPassword2024!" \
  host="robochef-rds.ap-south-1.rds.amazonaws.com"
```

Re-apply:

```bash
terraform apply -auto-approve
```

Expected output:

```
data.vault_generic_secret.robochef_db: Reading...
data.vault_generic_secret.chillbot_api: Reading...
data.vault_generic_secret.robochef_db: Read complete after 0s [id=secret/robochef-db]
data.vault_generic_secret.chillbot_api: Read complete after 0s [id=secret/chillbot-api]

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

config_files = [
  "/tmp/robochef-app-config.txt",
  "/tmp/chillbot-api-config.txt",
]
robochef_db_host = "robochef-rds.ap-south-1.rds.amazonaws.com"
robochef_db_username = "robochef"
robochef_db_password = <sensitive>
```

> **Key observation:** `robochef_db_password = <sensitive>` — the updated password is now in use. Zero changes to `.tf` files. No secrets were exposed in the terminal or Git history.

Verify the new password is active in Vault:

```bash
vault kv get -field=password secret/robochef-db
```

Expected:

```
NewPassword2024!
```

---

## Step 8 — The sensitive = true Requirement

From the real demo, when `sensitive = true` was missing from `robochef_db_password`, Terraform gave:

```
╷
│ Error: Output refers to sensitive values
│
│   on outputs.tf line 10:
│   10: output "robochef_db_password" {
│
│ To reduce the risk of accidentally exporting sensitive data, Terraform
│ requires that any root module output containing sensitive data be
│ explicitly marked as sensitive by setting the `sensitive` argument to true.
╵
```

**Fix:** Add `sensitive = true` to the output block (already done in our `outputs.tf`).

```hcl
output "robochef_db_password" {
  sensitive = true   # <-- this line is required
  value     = data.vault_generic_secret.robochef_db.data["password"]
}
```

This is a Terraform safety gate — it prevents you from accidentally printing secrets in CI logs or to the terminal.

---

## Key Concepts

**1. vault_generic_secret data source**

Reads any KV secret from Vault. The `path` argument matches exactly what you passed to `vault kv put`. The `.data` attribute returns a map of key-value pairs.

```hcl
data "vault_generic_secret" "robochef_db" {
  path = "secret/robochef-db"
}

# Access individual fields:
data.vault_generic_secret.robochef_db.data["password"]
```

**2. sensitive = true on outputs**

Required whenever an output value originates from Vault secret data. Terraform enforces this — without it, the apply fails with an error. The value still exists in state; it is just masked in terminal output and plan previews.

**3. Vault dev mode**

Started with `vault server -dev`. Characteristics:
- In-memory storage — all data lost on restart
- Auto-initialized and auto-unsealed
- Root token is whatever you pass with `-dev-root-token-id`
- Suitable for local testing only

**4. Token vs VAULT_TOKEN environment variable**

Hardcoding `token = "environment"` in `providers.tf` is acceptable for local dev but wrong for production. In production:
- Export `VAULT_TOKEN` as an environment variable and omit `token` from the provider block
- Or use Vault Agent to authenticate via AppRole, AWS IAM, or Kubernetes service account
- Or use a short-lived token fetched by your CI system at pipeline start

**5. KV secrets engine v1 vs v2**

Vault dev mode enables KV v2 by default under the `secret/` mount. Always use `vault kv get` and `vault kv put` (not `vault read` / `vault write`) with KV v2. In Terraform, `vault_generic_secret` works transparently with both versions — the path in the data source matches the CLI path.

**6. Why Vault with Terraform**

- Secrets never land in `.tf` files or Git
- Every secret read is logged with timestamp, caller identity, and IP address
- Access control: Vault policies control which Terraform roles can read which secrets
- Dynamic credentials: Vault can generate short-lived AWS access keys, database passwords, or TLS certificates on demand — no static secrets at all

---

## Destroy and Stop Vault

```bash
cd ~/terraform-vault-051-demo
terraform destroy -auto-approve
rm -rf .terraform
```

Stop the Vault dev server in Terminal 1: press **Ctrl+C**.

---

## Common Errors from the Demo

**1. "no vault token set on Client"**

```
Error: error reading from Vault: Error making API request.

URL: GET http://127.0.0.1:8200/v1/secret/data/robochef-db
Code: 403. Errors:

* 1 error occurred:
	* missing client token
```

Cause: The `token` argument is missing from the `provider "vault"` block and `VAULT_TOKEN` is not set.

Fix: Add `token = "environment"` to the provider block, or run `export VAULT_TOKEN="environment"` before applying.

**2. "no secret found at secret/robochef-db"**

```
Error: error reading from Vault: Error making API request.

URL: GET http://127.0.0.1:8200/v1/secret/data/robochef-db
Code: 404. Errors:

* secret not found
```

Cause: The secret path does not exist yet in Vault.

Fix: Run `vault kv put secret/robochef-db username="..." password="..." host="..."` before running `terraform apply`.

**3. "Get https://127.0.0.1:8200/..."**

```
Error: error reading from Vault: Get "https://127.0.0.1:8200/...": http: server gave HTTP response to HTTPS client
```

Cause: `VAULT_ADDR` is not set, so the Vault provider defaults to `https://127.0.0.1:8200`. The dev server runs on HTTP.

Fix: Set `export VAULT_ADDR="http://127.0.0.1:8200"` (note: `http`, not `https`), or set `address = "http://127.0.0.1:8200"` in the `provider "vault"` block.

**4. Missing sensitive = true on output**

```
Error: Output refers to sensitive values
```

Cause: A Vault secret value is used in an output without `sensitive = true`.

Fix: Add `sensitive = true` to the output block as shown in Step 8.
