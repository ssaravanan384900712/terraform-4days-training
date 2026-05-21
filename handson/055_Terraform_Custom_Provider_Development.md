# Lab 055 — Terraform Custom Provider Development
**By: Saravanan Sundaramoorthy**
**Environment:** Local (Go installed, no cloud credentials needed)
**Time:** ~30 minutes

---

## Topic

Every `provider` block you have ever written — `hashicorp/aws`, `hashicorp/random`, `hashicorp/vault` — is just a **binary** sitting on disk that Terraform spawns as a child process and talks to over **gRPC** using the Terraform Plugin Protocol. There is nothing magical about it.

This lab strips away all that mystery by building a minimal working provider from scratch using the **terraform-plugin-sdk v1**. The provider has a single resource, `example_server`, that reads a UUID from a public API. Once you build and install it, any Terraform configuration can use it exactly like any HashiCorp-published provider.

**Why does this matter for the robochef.co/saravanans platform?**

If robochef ever needs to manage a resource that no public provider covers — a proprietary Chef scheduling API, an in-house recipe-catalogue service, a custom IoT sensor registry — the team can write its own provider instead of resorting to brittle `null_resource` / `local-exec` hacks. Custom providers give you full state tracking, plan diffs, and drift detection for anything.

---

## How Terraform Calls a Provider (Mental Model)

```
┌─────────────────────────────────────────────────────────┐
│  terraform apply                                        │
│                                                         │
│  1. Reads required_providers block                      │
│  2. Locates binary in .terraform.d/plugins/...          │
│  3. Spawns binary as a child process                    │
│  4. Talks to it over gRPC (Terraform Plugin Protocol)   │
│  5. Calls Create / Read / Update / Delete as needed     │
└───────────────────┬─────────────────────────────────────┘
                    │ gRPC
┌───────────────────▼─────────────────────────────────────┐
│  terraform-provider-example  (our binary)               │
│                                                         │
│  plugin.Serve(...)         ← starts gRPC server         │
│    Provider()              ← returns schema              │
│      resourceServer()      ← CRUD handlers               │
└─────────────────────────────────────────────────────────┘
```

The key insight: **the provider IS the binary**. Terraform does not care what language it is written in or who published it as long as the binary speaks the plugin protocol. We use Go because the official SDKs are Go-first.

---

## Key Teaching Points

| Concept | Detail |
|---|---|
| Provider = binary | Terraform forks it, communicates over gRPC |
| Resource existence | Non-empty `d.SetId()` = resource exists; empty = deleted |
| CRUD contract | Create must call `SetId`; Delete must call `SetId("")` |
| SDK version | v1 (`terraform-plugin-sdk`) — simpler; v2 and plugin-framework used in production |
| Local install path | `~/.terraform.d/plugins/<hostname>/<namespace>/<type>/<version>/<OS_ARCH>/` |
| Unauthenticated warning | Expected for local providers — no registry GPG signature |

---

## What We Are Building

```text
Provider binary:    terraform-provider-example  (~26 MB, Go binary)
Provider source:    ~/terraform_custom_provider/
  main.go           entry point — starts gRPC plugin server
  provider.go       declares provider schema and resource map
  resource_server.go  CRUD handlers for "example_server" resource

Consumer project:   ~/tf_my_custom_provider/
  terraform.tf      required_providers block pointing at local registry
  main.tf           one "example_server" resource

Registry path:
  ~/.terraform.d/plugins/
    terraform-example.com/
      exampleprovider/
        example/
          1.0.0/
            linux_amd64/
              terraform-provider-example
```

---

## Prerequisites

```bash
# Verify Go is installed (need 1.18+)
go version
# go version go1.21.x linux/amd64

# Verify Terraform is installed
terraform version
```

If Go is not installed:

```bash
wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc
go version
```

---

## Step 1 — Create the Provider Source Directory

```bash
mkdir -p ~/terraform_custom_provider
cd ~/terraform_custom_provider
```

---

## Step 2 — Write the Three Source Files

### 2a. `main.go` — Entry Point

This file is the binary's `main` function. It calls `plugin.Serve`, which starts the gRPC server that Terraform connects to. You almost never need to change this file — it is boilerplate for every provider.

```bash
cat > ~/terraform_custom_provider/main.go << 'EOF'
package main

import (
    "github.com/hashicorp/terraform-plugin-sdk/plugin"
    "github.com/hashicorp/terraform-plugin-sdk/terraform"
)

func main() {
    plugin.Serve(&plugin.ServeOpts{
        ProviderFunc: func() terraform.ResourceProvider {
            return Provider()
        },
    })
}
EOF
```

**What this does:**

- `plugin.Serve` — blocks indefinitely, listening for Terraform's gRPC calls
- `ProviderFunc` — returns the provider schema when Terraform asks "what resources do you have?"
- The binary itself is passive: it waits for Terraform to call it, it never connects outward

---

### 2b. `provider.go` — Provider Schema

This file declares which resources this provider manages. In a real provider (`hashicorp/aws`), this map has hundreds of entries. Ours has one.

```bash
cat > ~/terraform_custom_provider/provider.go << 'EOF'
package main

import (
    "github.com/hashicorp/terraform-plugin-sdk/helper/schema"
)

func Provider() *schema.Provider {
    return &schema.Provider{
        ResourcesMap: map[string]*schema.Resource{
            "example_server": resourceServer(),
        },
    }
}
EOF
```

**What this does:**

- `schema.Provider` — the top-level object Terraform sees when it loads the provider
- `ResourcesMap` — maps resource type names to their schema + CRUD handlers
- The key `"example_server"` becomes the resource type used in HCL: `resource "example_server" "..."` 
- Provider-level configuration (credentials, regions) would go in `Schema` — we skip that here for simplicity

---

### 2c. `resource_server.go` — CRUD Handlers

This is where the actual work happens. This file defines:

1. The **schema** (what attributes the resource has)
2. The **CRUD functions** (what Terraform calls on create / read / update / delete)

```bash
cat > ~/terraform_custom_provider/resource_server.go << 'EOF'
package main

import (
    "github.com/hashicorp/terraform-plugin-sdk/helper/schema"
    "log"
    "net/http"
)

func resourceServer() *schema.Resource {
    return &schema.Resource{
        Create: resourceServerCreate,
        Read:   resourceServerRead,
        Update: resourceServerUpdate,
        Delete: resourceServerDelete,
        Schema: map[string]*schema.Schema{
            "uuid_count": &schema.Schema{
                Type:     schema.TypeString,
                Required: true,
            },
        },
    }
}

func resourceServerCreate(d *schema.ResourceData, m interface{}) error {
    uuid_count := d.Get("uuid_count").(string)
    d.SetId(uuid_count)
    resp, err := http.Get("https://www.uuidtools.com/api/generate/v1/count/" + uuid_count)
    if err != nil {
        log.Fatal(err)
    }
    defer resp.Body.Close()
    return resourceServerRead(d, m)
}

func resourceServerRead(d *schema.ResourceData, m interface{}) error { return nil }
func resourceServerUpdate(d *schema.ResourceData, m interface{}) error { return resourceServerRead(d, m) }
func resourceServerDelete(d *schema.ResourceData, m interface{}) error { d.SetId(""); return nil }
EOF
```

**Deep dive — the CRUD contract:**

| Function | When called | What it must do |
|---|---|---|
| `Create` | `terraform apply` on a new resource | Call `d.SetId(someValue)` — this tells Terraform the resource now exists |
| `Read` | Refresh, plan, import | Read remote state; call `d.SetId("")` if the resource is gone |
| `Update` | `terraform apply` when attributes changed | Update remote resource; optionally call `d.SetId` |
| `Delete` | `terraform destroy` | Call `d.SetId("")` — this tells Terraform the resource is gone |

**The `d.SetId` rule is the most important thing in provider development:**

```
d.SetId("some-value")   →  resource EXISTS in state
d.SetId("")             →  resource DELETED — Terraform removes it from state
```

If `Create` forgets to call `SetId`, Terraform will think the resource was never created and will try to create it again on the next apply. If `Delete` forgets to call `SetId("")`, the resource will remain in state forever even after being destroyed.

**What `resourceServerCreate` does here:**

1. Reads the `uuid_count` attribute from the config (`d.Get`)
2. Uses the value as the resource ID (`d.SetId`)
3. Makes an HTTP GET to the UUID API — simulating a "real" API call (like creating a Chef session for robochef.co/saravanans)
4. Calls `resourceServerRead` to refresh state — the standard pattern

---

## Step 3 — Initialise Go Modules and Download the SDK

```bash
cd ~/terraform_custom_provider

# Initialise Go module — names the module (can be anything, conventionally matches repo path)
go mod init terraform-provider-example
```

Expected output:
```
go: creating new go.mod: module terraform-provider-example
```

```bash
# Download terraform-plugin-sdk v1 and all its dependencies
go mod tidy
```

Expected output (first run — downloads ~60 packages):
```
go: finding module for package github.com/hashicorp/terraform-plugin-sdk/plugin
go: finding module for package github.com/hashicorp/terraform-plugin-sdk/terraform
go: finding module for package github.com/hashicorp/terraform-plugin-sdk/helper/schema
go: found github.com/hashicorp/terraform-plugin-sdk in github.com/hashicorp/terraform-plugin-sdk v1.17.2
go: downloading github.com/hashicorp/terraform-plugin-sdk v1.17.2
...
```

The key line is `terraform-plugin-sdk v1.17.2` — this is the v1 SDK, the simplest version to learn with. Production providers now use v2 or `terraform-plugin-framework`, but v1 is ideal for understanding the fundamentals.

```bash
# Format all Go source files (optional but good habit)
go fmt
```

Expected output:
```
main.go
provider.go
resource_server.go
```

---

## Step 4 — Build the Provider Binary

```bash
cd ~/terraform_custom_provider
go build
```

Expected output: **nothing** (Go is silent on success)

Check the binary was created:

```bash
ls -lh ~/terraform_custom_provider/
```

Expected output:
```
total 28M
-rw-r--r-- 1 user user  178 May 21 10:00 go.mod
-rw-r--r-- 1 user user 5.2K May 21 10:00 go.sum
-rw-r--r-- 1 user user  301 May 21 10:00 main.go
-rw-r--r-- 1 user user  224 May 21 10:00 provider.go
-rw-r--r-- 1 user user  703 May 21 10:00 resource_server.go
-rwxr-xr-x 1 user user  26M May 21 10:00 terraform-provider-example
```

The binary is ~26 MB because Go links the entire Go runtime and all SDK dependencies statically. The binary is self-contained — no runtime dependencies, no shared libraries needed.

---

## Step 5 — Install the Provider into the Local Plugin Registry

Terraform looks for local providers in a specific path. The path format encodes:

```
~/.terraform.d/plugins/
  <hostname>/              ← fictional registry hostname (not contacted over network)
    <namespace>/           ← organisation or team name
      <type>/              ← short provider name (matches "example" in required_providers)
        <version>/         ← semver version string
          <OS_ARCH>/       ← go tool's GOOS_GOARCH format
            terraform-provider-<type>   ← binary name (must match exactly)
```

For our provider:

```
~/.terraform.d/plugins/
  terraform-example.com/
    exampleprovider/
      example/
        1.0.0/
          linux_amd64/
            terraform-provider-example
```

Create the directory and copy the binary:

```bash
mkdir -p ~/.terraform.d/plugins/terraform-example.com/exampleprovider/example/1.0.0/linux_amd64

cp ~/terraform_custom_provider/terraform-provider-example \
   ~/.terraform.d/plugins/terraform-example.com/exampleprovider/example/1.0.0/linux_amd64/
```

Verify:

```bash
ls -lh ~/.terraform.d/plugins/terraform-example.com/exampleprovider/example/1.0.0/linux_amd64/
```

Expected output:
```
-rwxr-xr-x 1 user user 26M May 21 10:00 terraform-provider-example
```

**Why this specific path?** Terraform's filesystem mirror protocol requires this exact layout so that `terraform init` can locate the binary without contacting any registry server. The `hostname` portion (`terraform-example.com`) is a fictional address — Terraform never performs a DNS lookup or HTTP request to it when using local filesystem mirrors.

---

## Step 6 — Create the Consumer Terraform Project

```bash
mkdir -p ~/tf_my_custom_provider
cd ~/tf_my_custom_provider
```

### 6a. `terraform.tf` — Provider Requirements

```bash
cat > ~/tf_my_custom_provider/terraform.tf << 'EOF'
terraform {
  required_providers {
    example = {
      version = "~> 1.0.0"
      source  = "terraform-example.com/exampleprovider/example"
    }
  }
}
EOF
```

**Breaking down the `source` value:**

```
terraform-example.com / exampleprovider / example
      hostname              namespace       type
```

- `hostname` — where Terraform would look in a real registry; here it matches our local directory
- `namespace` — the organisation (`exampleprovider`)
- `type` — the short name used in `required_providers` (`example`) and by convention the suffix of the binary name (`terraform-provider-example`)

The `version = "~> 1.0.0"` constraint means "1.0.x but not 1.1.0 or higher".

---

### 6b. `main.tf` — Resource Configuration

```bash
cat > ~/tf_my_custom_provider/main.tf << 'EOF'
resource "example_server" "demoinstance" {
  uuid_count = "1"
}
EOF
```

This creates one `example_server` resource. The attribute `uuid_count = "1"` tells our provider to fetch 1 UUID from the API — simulating a lightweight API call (in a real robochef.co/saravanans provider you might pass a recipe ID or session token here instead).

---

## Step 7 — `terraform init`

```bash
cd ~/tf_my_custom_provider
terraform init
```

Expected output:

```
Initializing the backend...

Initializing provider plugins...
- Finding terraform-example.com/exampleprovider/example versions matching "~> 1.0.0"...
- Installing terraform-example.com/exampleprovider/example v1.0.0...
- Installed terraform-example.com/exampleprovider/example v1.0.0 (unauthenticated)

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your configuration. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
```

**Notice: `(unauthenticated)`** — this is **expected and normal** for local providers.

When Terraform downloads a provider from the official registry (registry.terraform.io), it verifies a GPG signature from HashiCorp to confirm the binary has not been tampered with. Our local binary has no registry signature, so Terraform skips the verification and prints `(unauthenticated)`. It is not an error — it just means "I found the binary locally and used it without cryptographic verification".

In a team or CI environment you can suppress the warning by adding the provider to a `dev_overrides` block in `~/.terraformrc`, but for a learning lab the `(unauthenticated)` message is fine.

---

## Step 8 — `terraform plan`

```bash
cd ~/tf_my_custom_provider
terraform plan
```

Expected output:

```
Terraform used the selected providers to generate the following execution plan.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # example_server.demoinstance will be created
  + resource "example_server" "demoinstance" {
      + id         = (known after apply)
      + uuid_count = "1"
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

Terraform calls our provider's `Schema` definition to produce the plan diff. The `id` field is always present in every resource and is set by `d.SetId()` during Create — that is why it shows `(known after apply)`.

---

## Step 9 — `terraform apply`

```bash
cd ~/tf_my_custom_provider
terraform apply --auto-approve
```

Expected output:

```
Terraform used the selected providers to generate the following execution plan.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # example_server.demoinstance will be created
  + resource "example_server" "demoinstance" {
      + id         = (known after apply)
      + uuid_count = "1"
    }

Plan: 1 to add, 0 to change, 0 to destroy.
example_server.demoinstance: Creating...
example_server.demoinstance: Creation complete after 0s [id=1]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

**What happened:**

1. Terraform called our `resourceServerCreate` function
2. `resourceServerCreate` set the ID to `"1"` (the value of `uuid_count`)
3. It made an HTTP GET to `https://www.uuidtools.com/api/generate/v1/count/1`
4. Called `resourceServerRead` (which is a no-op in our demo — returns nil)
5. Terraform wrote the resource to state with `id = "1"`

Inspect the state file to see how Terraform recorded the resource:

```bash
cat ~/tf_my_custom_provider/terraform.tfstate
```

Expected output (pretty-printed):

```json
{
  "version": 4,
  "terraform_version": "1.x.x",
  "serial": 1,
  "lineage": "...",
  "outputs": {},
  "resources": [
    {
      "mode": "managed",
      "type": "example_server",
      "name": "demoinstance",
      "provider": "provider[\"terraform-example.com/exampleprovider/example\"]",
      "instances": [
        {
          "schema_version": 0,
          "attributes": {
            "id": "1",
            "uuid_count": "1"
          },
          "sensitive_attributes": []
        }
      ]
    }
  ]
}
```

The `id = "1"` in state is exactly what `d.SetId("1")` wrote. As long as `id` is non-empty, Terraform considers this resource to exist.

---

## Step 10 — `terraform destroy` and Cleanup

```bash
cd ~/tf_my_custom_provider
terraform destroy
```

When prompted, type `yes`.

Expected output:

```
Terraform used the selected providers to generate the following execution plan.
Resource actions are indicated with the following symbols:
  - destroy

Terraform will perform the following actions:

  # example_server.demoinstance will be destroyed
  - resource "example_server" "demoinstance" {
      - id         = "1" -> null
      - uuid_count = "1" -> null
    }

Plan: 0 to add, 0 to change, 1 to destroy.

Do you really want to destroy all resources?
  Terraform will destroy all resources shown above.
  Enter a value: yes

example_server.demoinstance: Destroying... [id=1]
example_server.demoinstance: Destruction complete after 0s

Destroy complete! Resources: 1 destroyed.
```

**What happened during destroy:**

1. Terraform called our `resourceServerDelete` function
2. `resourceServerDelete` called `d.SetId("")` — signalling "this resource no longer exists"
3. Terraform removed the resource from state
4. State file now has an empty resources array

Clean up the `.terraform` cache directory:

```bash
rm -rf ~/tf_my_custom_provider/.terraform
```

---

## Understanding `d.SetId` — The Core State Mechanism

This is the single most important concept in Terraform provider development:

```go
// Resource EXISTS — ID is set to any non-empty string
d.SetId("some-identifier")

// Resource DELETED — empty string signals removal
d.SetId("")

// Check if resource still exists (in Read)
if d.Id() == "" {
    // resource was deleted externally — Terraform will plan to recreate
    return nil
}
```

**Lifecycle walkthrough for `example_server.demoinstance`:**

```
terraform apply (new resource)
  → Create called
  → d.SetId("1")         ← state now has id="1"
  → resource is tracked

terraform apply (no changes)
  → Read called
  → returns nil (no change)
  → id="1" stays in state

terraform apply (uuid_count changed to "3")
  → Update called
  → d.SetId("3")         ← id updated to "3"
  → state now has id="3"

terraform destroy
  → Delete called
  → d.SetId("")          ← id is now empty
  → Terraform removes resource from state
```

---

## SDK Versions — v1 vs v2 vs Plugin Framework

| SDK | Import path | Best for |
|---|---|---|
| v1 (this lab) | `github.com/hashicorp/terraform-plugin-sdk` | Learning; deprecated but still works |
| v2 | `github.com/hashicorp/terraform-plugin-sdk/v2` | Most existing community providers |
| terraform-plugin-framework | `github.com/hashicorp/terraform-plugin-framework` | New providers; required for Terraform 1.x features like deferred actions |

The code structure is nearly identical between v1 and v2 — upgrading is mostly a find-and-replace of import paths. The plugin-framework is a more significant rewrite with a different API design, but the CRUD + `SetId` concepts carry over.

---

## Extending This Provider — Ideas for robochef.co/saravanans

Once you understand the pattern, you can turn any HTTP API into a Terraform provider:

```go
// Instead of UUID API, call robochef recipe API
func resourceServerCreate(d *schema.ResourceData, m interface{}) error {
    recipeName := d.Get("recipe_name").(string)
    sessionID  := d.Get("session_id").(string)

    // POST to internal robochef API
    resp, err := http.Post(
        "https://api.robochef.co/saravanans/sessions",
        "application/json",
        strings.NewReader(`{"recipe":"`+recipeName+`"}`),
    )
    if err != nil {
        return fmt.Errorf("failed to create session: %w", err)
    }
    defer resp.Body.Close()

    // Parse response and set ID
    var result map[string]string
    json.NewDecoder(resp.Body).Decode(&result)
    d.SetId(result["session_id"])    // non-empty = resource exists in state

    return resourceServerRead(d, m)
}
```

This gives robochef infrastructure-as-code control over Chef sessions, recipe deployments, or IoT sensor registrations — with full `plan` / `apply` / `destroy` lifecycle management and drift detection.

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| `Could not find provider` | Binary not in correct path | Check `~/.terraform.d/plugins/` path matches `source` in `required_providers` |
| `Error: could not query provider registry` | Terraform tried the network | Ensure `source` hostname matches the local path exactly |
| `(unauthenticated)` warning | No GPG signature for local provider | Expected — not an error |
| `go build` fails — cannot find package | `go mod tidy` not run | Run `go mod tidy` first |
| `permission denied` on binary | Binary not executable | Run `chmod +x terraform-provider-example` |
| `go: command not found` | Go not in PATH | `export PATH=$PATH:/usr/local/go/bin` |

---

## Summary

```
Provider development workflow:

  1. Write Go code (main.go + provider.go + resource_*.go)
  2. go mod init && go mod tidy   ← set up Go modules
  3. go build                     ← produces the binary (~26 MB)
  4. Copy binary to ~/.terraform.d/plugins/<host>/<ns>/<type>/<ver>/<arch>/
  5. Write terraform.tf with required_providers source matching the path
  6. terraform init               ← finds binary, shows (unauthenticated) — normal
  7. terraform apply              ← Terraform calls your CRUD functions via gRPC
  8. terraform destroy            ← calls Delete, d.SetId("") removes from state
  9. rm -rf .terraform            ← clean up plugin cache
```

**Core rules to remember:**

- A provider is just a binary. Terraform forks it and talks gRPC.
- `d.SetId("x")` = resource exists. `d.SetId("")` = resource deleted.
- Create **must** call SetId. Delete **must** call SetId with empty string.
- Local providers always show `(unauthenticated)` — this is fine.
- v1 SDK for learning; v2 or plugin-framework for production.
