# 038 — Terraform Loops: for_each, for Expressions & Dynamic Blocks

**By:** Saravanan Sundaramoorthy
**Environment:** Local (no cloud credentials needed)
**Time:** ~20 min

---

## Concept

Terraform has three distinct looping mechanisms. Each works at a different layer:

```
┌───────────────────┬──────────────────────────────────────────────────────┐
│ Loop type         │ Where it lives           │ What it produces           │
├───────────────────┼──────────────────────────┼────────────────────────────┤
│ for_each          │ on a resource block      │ Multiple resource instances │
│ for expression    │ inside locals / outputs  │ Transformed list or map    │
│ dynamic block     │ inside a resource block  │ Repeated nested blocks     │
└───────────────────┴──────────────────────────┴────────────────────────────┘
```

All three use local and random providers — no cloud account needed.

---

## Prerequisites

Create a fresh project:

```bash
mkdir -p ~/tf_works/038_loops
cd ~/tf_works/038_loops
```

```bash
cat > main.tf << 'EOF'
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
EOF
```

```bash
terraform init
```

```
Initializing provider plugins...
- Installed hashicorp/local v2.5.1
- Installed hashicorp/random v3.6.2

Terraform has been successfully initialized!
```

---

## Part 1 — for_each on Resources

`for_each` turns one resource block into multiple named instances — one per key in a map or set.

### 1a — for_each with a map of objects

The most powerful form: a map where each value is itself a map of attributes.

```bash
cat >> main.tf << 'EOF'

# ── Part 1a: for_each with a map of objects ───────────────────────────────────

variable "sites" {
  description = "Sites managed on robochef infrastructure"
  type = map(object({
    domain = string
    owner  = string
  }))
  default = {
    robochef = {
      domain = "robochef.co"
      owner  = "saravanans"
    }
    chillbot = {
      domain = "chillbotindia.com"
      owner  = "saravanans"
    }
    personal = {
      domain = "saravanans.dev"
      owner  = "saravanans"
    }
  }
}

resource "local_file" "site_config" {
  for_each = var.sites

  filename = "/tmp/${each.key}-config.txt"
  content  = "domain=${each.value.domain}\nowner=${each.value.owner}\nmanaged_by=terraform\n"
}

output "site_files" {
  value = { for k, v in local_file.site_config : k => v.filename }
}
EOF
```

### How each.key and each.value work

```
var.sites = {
  "robochef" = { domain = "robochef.co",      owner = "saravanans" }
  "chillbot" = { domain = "chillbotindia.com", owner = "saravanans" }
  "personal" = { domain = "saravanans.dev",    owner = "saravanans" }
}

for_each = var.sites
             │
             └── Iterates over each map entry:

  Iteration 1:
    each.key   = "robochef"
    each.value = { domain = "robochef.co", owner = "saravanans" }
    each.value.domain = "robochef.co"
    each.value.owner  = "saravanans"

  Iteration 2:
    each.key   = "chillbot"
    each.value = { domain = "chillbotindia.com", owner = "saravanans" }

  Iteration 3:
    each.key   = "personal"
    each.value = { domain = "saravanans.dev", owner = "saravanans" }
```

```bash
terraform apply -auto-approve
```

```
local_file.site_config["chillbot"]: Creating...
local_file.site_config["personal"]: Creating...
local_file.site_config["robochef"]: Creating...
local_file.site_config["chillbot"]: Creation complete after 0s
local_file.site_config["personal"]: Creation complete after 0s
local_file.site_config["robochef"]: Creation complete after 0s

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

site_files = {
  "chillbot" = "/tmp/chillbot-config.txt"
  "personal" = "/tmp/personal-config.txt"
  "robochef" = "/tmp/robochef-config.txt"
}
```

Check state — resources are keyed by name, not index:

```bash
terraform state list
```

```
local_file.site_config["chillbot"]
local_file.site_config["personal"]
local_file.site_config["robochef"]
```

Verify a file:

```bash
cat /tmp/robochef-config.txt
```

```
domain=robochef.co
owner=saravanans
managed_by=terraform
```

### Referencing a single for_each instance

```bash
terraform state show 'local_file.site_config["robochef"]'
```

```
# local_file.site_config["robochef"]:
resource "local_file" "site_config" {
    content  = "domain=robochef.co\nowner=saravanans\nmanaged_by=terraform\n"
    filename = "/tmp/robochef-config.txt"
    id       = "..."
}
```

In HCL, reference a specific instance like this:

```hcl
# Reference the robochef file path in another resource:
local_file.site_config["robochef"].filename
```

### 1b — for_each with random_string (token per site)

```bash
cat >> main.tf << 'EOF'

# ── Part 1b: for_each with random_string ──────────────────────────────────────

resource "random_string" "site_token" {
  for_each = var.sites

  length  = 24
  special = false
  upper   = true
}

output "site_tokens" {
  value     = { for k, v in random_string.site_token : k => v.result }
  sensitive = true
}
EOF
```

```bash
terraform apply -auto-approve
```

```
random_string.site_token["chillbot"]: Creating...
random_string.site_token["personal"]: Creating...
random_string.site_token["robochef"]: Creating...

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

```bash
terraform output -json site_tokens | python3 -m json.tool
```

```json
{
    "chillbot": "Kp3NvXqMwLrBsYtCuAzDf8Ge",
    "personal": "Hj7MkRnQvWpLsXtYuAzBcDe2",
    "robochef": "Xm5BrTqKwNpLsYtVuAzCdEf9G"
}
```

Each site gets its own unique token, addressed by name.

---

## Part 2 — for Expressions: Transforming Collections

`for` expressions live inside `locals`, `output`, and variable defaults. They transform lists and maps into new shapes.

### Syntax forms

```
List output:
  [for <item> in <collection> : <expression>]
  [for <item> in <collection> : <expression> if <condition>]

Map output:
  { for <item> in <collection> : <key_expr> => <value_expr> }
  { for <key>, <value> in <map> : <key_expr> => <value_expr> }
```

### Demo

```bash
cat >> main.tf << 'EOF'

# ── Part 2: for expressions ───────────────────────────────────────────────────

variable "usernames" {
  description = "robochef platform users"
  type        = list(string)
  default     = ["saravanans", "robochef_admin", "chillbot_user", "guest"]
}

locals {
  # List: uppercase every username
  upper_users = [for u in var.usernames : upper(u)]

  # List with filter: only usernames longer than 10 characters
  filtered_users = [for u in var.usernames : u if length(u) > 10]

  # Map: username => its character length
  user_length_map = { for u in var.usernames : u => length(u) }

  # Map: username => generated email address
  email_map = { for u in var.usernames : u => "${u}@robochef.co" }

  # Map from map: site => uppercase domain
  upper_domains = { for k, v in var.sites : k => upper(v.domain) }

  # List: only site keys where owner is "saravanans"
  owned_sites = [for k, v in var.sites : k if v.owner == "saravanans"]
}

output "upper_users"    { value = local.upper_users }
output "filtered_users" { value = local.filtered_users }
output "user_length_map" { value = local.user_length_map }
output "email_map"       { value = local.email_map }
output "upper_domains"   { value = local.upper_domains }
output "owned_sites"     { value = local.owned_sites }
EOF
```

```bash
terraform apply -auto-approve
```

```
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

upper_users = [
  "SARAVANANS",
  "ROBOCHEF_ADMIN",
  "CHILLBOT_USER",
  "GUEST",
]

filtered_users = [
  "robochef_admin",
  "chillbot_user",
]

user_length_map = {
  "chillbot_user"  = 13
  "guest"          = 5
  "robochef_admin" = 14
  "saravanans"     = 10
}

email_map = {
  "chillbot_user"  = "chillbot_user@robochef.co"
  "guest"          = "guest@robochef.co"
  "robochef_admin" = "robochef_admin@robochef.co"
  "saravanans"     = "saravanans@robochef.co"
}

upper_domains = {
  "chillbot" = "CHILLBOTINDIA.COM"
  "personal" = "SARAVANANS.DEV"
  "robochef" = "ROBOCHEF.CO"
}

owned_sites = [
  "chillbot",
  "personal",
  "robochef",
]
```

### Explore for expressions interactively

`terraform console` is a live REPL — try for expressions without applying:

```bash
terraform console
```

```hcl
# List: double every username length
> [for u in var.usernames : length(u) * 2]
[
  20,
  28,
  26,
  10,
]

# Map: only users longer than 8 chars => email
> { for u in var.usernames : u => "${u}@robochef.co" if length(u) > 8 }
{
  "chillbot_user" = "chillbot_user@robochef.co"
  "robochef_admin" = "robochef_admin@robochef.co"
  "saravanans" = "saravanans@robochef.co"
}

# Nested: for expression over for_each resource outputs
> { for k, v in local_file.site_config : k => v.content }
{
  "chillbot" = "domain=chillbotindia.com\nowner=saravanans\nmanaged_by=terraform\n"
  "personal" = "domain=saravanans.dev\nowner=saravanans\nmanaged_by=terraform\n"
  "robochef" = "domain=robochef.co\nowner=saravanans\nmanaged_by=terraform\n"
}
```

Press `Ctrl+D` or type `exit` to leave console.

### for expression cheat sheet

```
Expression                                     Result type   Example output
─────────────────────────────────────────────  ────────────  ───────────────────────────────────
[for x in list : x]                           list          same list
[for x in list : upper(x)]                    list          uppercased list
[for x in list : x if condition]              list          filtered list
{ for x in list : x => length(x) }            map           name => length map
{ for k, v in map : k => v.attr }             map           project attribute from map values
{ for k, v in map : k => v if condition }     map           filtered map
[for k, v in map : k]                         list          just the keys
[for k, v in map : v.attr]                    list          just one attribute from each value
```

---

## Part 3 — Dynamic Blocks

`dynamic` blocks generate repeated nested configuration blocks inside a resource. They are the loop for **block arguments** (not top-level resources).

### When you need dynamic blocks

Some resources have repeated nested blocks:

```hcl
# This is verbose — what if you have 10 ports?
resource "aws_security_group" "web" {
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

With a `dynamic` block, that becomes:

```hcl
variable "ports" {
  default = [80, 443, 8080]
}

resource "aws_security_group" "web" {
  dynamic "ingress" {
    for_each = var.ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
}
```

```
dynamic "ingress" {         ← block label = nested block name
  for_each = var.ports      ← collection to iterate
  content {                 ← required wrapper — defines one block's content
    from_port = ingress.value  ← ingress = iterator name (same as block label)
  }
}
```

### Demonstrating dynamic block logic using local_file

The `local_file` provider does not have repeated nested blocks, so we simulate the pattern: generate the content that dynamic blocks would produce, write it to a file, and show the real dynamic block syntax side-by-side.

```bash
cat >> main.tf << 'EOF'

# ── Part 3: dynamic block pattern (simulation + real syntax) ──────────────────

variable "ports" {
  description = "Ports to allow through robochef firewall"
  type        = list(number)
  default     = [80, 443, 8080]
}

variable "environments_fw" {
  description = "Environments to generate firewall rules for"
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}

locals {
  # Simulate what dynamic ingress blocks would allow
  port_rules = [for p in var.ports : "ALLOW TCP ${p} FROM 0.0.0.0/0"]

  # Cross product: environment × port
  env_port_rules = flatten([
    for env in var.environments_fw : [
      for p in var.ports : "ENV=${env} ALLOW TCP ${p}"
    ]
  ])
}

resource "local_file" "firewall_rules" {
  filename = "/tmp/robochef-firewall.txt"
  content  = join("\n", local.port_rules)
}

resource "local_file" "env_firewall_rules" {
  filename = "/tmp/robochef-env-firewall.txt"
  content  = join("\n", local.env_port_rules)
}

output "firewall_file"     { value = local_file.firewall_rules.filename }
output "env_firewall_file" { value = local_file.env_firewall_rules.filename }
output "port_rules"        { value = local.port_rules }
output "env_port_rules"    { value = local.env_port_rules }
EOF
```

```bash
terraform apply -auto-approve
```

```
local_file.env_firewall_rules: Creating...
local_file.firewall_rules: Creating...
local_file.env_firewall_rules: Creation complete after 0s
local_file.firewall_rules: Creation complete after 0s

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

firewall_file     = "/tmp/robochef-firewall.txt"
env_firewall_file = "/tmp/robochef-env-firewall.txt"

port_rules = [
  "ALLOW TCP 80 FROM 0.0.0.0/0",
  "ALLOW TCP 443 FROM 0.0.0.0/0",
  "ALLOW TCP 8080 FROM 0.0.0.0/0",
]

env_port_rules = [
  "ENV=dev ALLOW TCP 80",
  "ENV=dev ALLOW TCP 443",
  "ENV=dev ALLOW TCP 8080",
  "ENV=staging ALLOW TCP 80",
  "ENV=staging ALLOW TCP 443",
  "ENV=staging ALLOW TCP 8080",
  "ENV=prod ALLOW TCP 80",
  "ENV=prod ALLOW TCP 443",
  "ENV=prod ALLOW TCP 8080",
]
```

```bash
cat /tmp/robochef-firewall.txt
```

```
ALLOW TCP 80 FROM 0.0.0.0/0
ALLOW TCP 443 FROM 0.0.0.0/0
ALLOW TCP 8080 FROM 0.0.0.0/0
```

### Real dynamic block syntax (AWS context — not applied here)

This is what you will write when working with AWS Security Groups:

```hcl
variable "ports" {
  default = [80, 443, 8080]
}

resource "aws_security_group" "robochef_web" {
  name        = "robochef-web-sg"
  description = "robochef web tier"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.ports         # iterate over port list
    content {
      description = "Allow port ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

Produces the same three ingress blocks as the verbose version — driven by `var.ports`.

### dynamic block with a map (labels as iterator name)

```hcl
variable "ingress_rules" {
  default = {
    http  = { port = 80,   cidr = "0.0.0.0/0" }
    https = { port = 443,  cidr = "0.0.0.0/0" }
    admin = { port = 8080, cidr = "10.0.0.0/8" }
  }
}

resource "aws_security_group" "robochef_web" {
  dynamic "ingress" {
    for_each = var.ingress_rules
    iterator = rule               # ← rename iterator from "ingress" to "rule"
    content {
      description = rule.key                   # "http", "https", "admin"
      from_port   = rule.value.port
      to_port     = rule.value.port
      protocol    = "tcp"
      cidr_blocks = [rule.value.cidr]
    }
  }
}
```

`iterator = rule` renames the loop variable from the default (block label name) to `rule`, which reads more clearly.

### Nested dynamic blocks

```hcl
# Two-level nesting: environments × ports
dynamic "ingress" {
  for_each = var.environments
  iterator = env
  content {
    description = "Env: ${env.key}"
    # nested dynamic inside ingress is unusual but possible
    from_port = env.value.base_port
    to_port   = env.value.base_port
    protocol  = "tcp"
    cidr_blocks = [env.value.cidr]
  }
}
```

> Keep nested dynamics simple — two levels deep is usually the maximum before it becomes hard to read.

---

## Part 4 — count vs for_each: When to Use Which

```
count = 3                              for_each = var.sites
──────────────────                     ─────────────────────────────────────
site_config[0]  = "/tmp/..."           site_config["robochef"] = "/tmp/..."
site_config[1]  = "/tmp/..."           site_config["chillbot"] = "/tmp/..."
site_config[2]  = "/tmp/..."           site_config["personal"] = "/tmp/..."
      │                                        │
 Index-based (fragile)                  Key-based (stable)

Remove item at index 0:                Remove "chillbot":
  [1] shifts to [0]                      "robochef" untouched
  [2] shifts to [1]                      "personal" untouched
  Both recreated!                        Only "chillbot" destroyed
```

### Decision table

```
┌────────────────────────────────────┬────────────┬───────────┐
│ Scenario                           │ count      │ for_each  │
├────────────────────────────────────┼────────────┼───────────┤
│ N identical copies of a resource   │ YES        │ possible  │
│ Resources with distinct identities │ no         │ YES       │
│ Conditional create (0 or 1)        │ YES        │ possible  │
│ Add/remove items without cascades  │ no         │ YES       │
│ Input is a list of strings         │ YES        │ toset()   │
│ Input is a map                     │ no         │ YES       │
│ Input is a set                     │ no         │ YES       │
│ Need count.index for names         │ YES        │ no        │
│ Stable state keys after changes    │ no         │ YES       │
└────────────────────────────────────┴────────────┴───────────┘
```

### count for conditional creation

The only pattern where `count` beats `for_each`:

```hcl
variable "enable_debug_log" {
  type    = bool
  default = false
}

resource "local_file" "debug_log" {
  count    = var.enable_debug_log ? 1 : 0
  filename = "/tmp/robochef-debug.log"
  content  = "debug enabled\n"
}
```

```bash
# Resource not created when false:
terraform apply -auto-approve -var='enable_debug_log=false'
# → Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

# Resource created when true:
terraform apply -auto-approve -var='enable_debug_log=true'
# → local_file.debug_log[0]: Creating...
```

### for_each from a list: toset()

`for_each` requires a map or set — not a plain list. Convert with `toset()`:

```hcl
variable "regions" {
  type    = list(string)
  default = ["us-east-1", "eu-west-1", "ap-south-1"]
}

resource "random_string" "region_id" {
  for_each = toset(var.regions)   # ← convert list → set

  length  = 8
  special = false
}

output "region_ids" {
  value = { for k, v in random_string.region_id : k => v.result }
}
```

```
With toset():
  random_string.region_id["ap-south-1"]
  random_string.region_id["eu-west-1"]
  random_string.region_id["us-east-1"]

Each key is the region name — removing "eu-west-1" only destroys that one.
```

---

## Part 5 — Putting It All Together

A complete example combining all three loops:

```bash
cat >> main.tf << 'EOF'

# ── Part 5: combined example ──────────────────────────────────────────────────

variable "teams" {
  description = "robochef engineering teams"
  default = {
    backend  = { lead = "saravanans", size = 4 }
    frontend = { lead = "saravanans", size = 3 }
    devops   = { lead = "saravanans", size = 2 }
  }
}

locals {
  # for expression: build member list per team
  team_emails = {
    for team, info in var.teams :
    team => "${info.lead}+${team}@robochef.co"
  }

  # for expression: teams larger than 3 people
  large_teams = [for team, info in var.teams : team if info.size > 3]

  # for expression: total headcount
  total_headcount = sum([for team, info in var.teams : info.size])
}

# for_each: one config file per team
resource "local_file" "team_config" {
  for_each = var.teams

  filename = "/tmp/robochef-team-${each.key}.txt"
  content  = <<-CONFIG
    team=${each.key}
    lead=${each.value.lead}
    size=${each.value.size}
    email=${local.team_emails[each.key]}
  CONFIG
}

# for_each: one API token per team
resource "random_string" "team_token" {
  for_each = var.teams

  length  = 32
  special = false
}

output "team_config_files" {
  value = { for k, v in local_file.team_config : k => v.filename }
}

output "team_emails"      { value = local.team_emails }
output "large_teams"      { value = local.large_teams }
output "total_headcount"  { value = local.total_headcount }

output "team_tokens" {
  value     = { for k, v in random_string.team_token : k => v.result }
  sensitive = true
}
EOF
```

```bash
terraform apply -auto-approve
```

```
local_file.team_config["backend"]: Creating...
local_file.team_config["devops"]: Creating...
local_file.team_config["frontend"]: Creating...
random_string.team_token["backend"]: Creating...
random_string.team_token["devops"]: Creating...
random_string.team_token["frontend"]: Creating...
...all created...

Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:

team_config_files = {
  "backend"  = "/tmp/robochef-team-backend.txt"
  "devops"   = "/tmp/robochef-team-devops.txt"
  "frontend" = "/tmp/robochef-team-frontend.txt"
}

team_emails = {
  "backend"  = "saravanans+backend@robochef.co"
  "devops"   = "saravanans+devops@robochef.co"
  "frontend" = "saravanans+frontend@robochef.co"
}

large_teams = [
  "backend",
]

total_headcount = 9
```

```bash
cat /tmp/robochef-team-backend.txt
```

```
team=backend
lead=saravanans
size=4
email=saravanans+backend@robochef.co
```

---

## Loop Mechanisms at a Glance

```
┌──────────────────┬─────────────────────────────────────┬──────────────────────────────────────┐
│ Mechanism        │ Syntax                              │ Output                               │
├──────────────────┼─────────────────────────────────────┼──────────────────────────────────────┤
│ for_each         │ for_each = map_or_set               │ Multiple resource instances           │
│ on resource      │ each.key / each.value               │ Addressed as resource["key"]         │
├──────────────────┼─────────────────────────────────────┼──────────────────────────────────────┤
│ for expression   │ [for x in list : expr]              │ New list                             │
│ (list output)    │ [for x in list : expr if cond]      │ Filtered list                        │
├──────────────────┼─────────────────────────────────────┼──────────────────────────────────────┤
│ for expression   │ { for x in list : k => v }          │ New map                              │
│ (map output)     │ { for k, v in map : k => expr }     │ Transformed map                      │
├──────────────────┼─────────────────────────────────────┼──────────────────────────────────────┤
│ dynamic block    │ dynamic "block_name" {              │ Repeated nested blocks in resource   │
│                  │   for_each = collection             │                                      │
│                  │   content { ... }                   │                                      │
│                  │ }                                   │                                      │
├──────────────────┼─────────────────────────────────────┼──────────────────────────────────────┤
│ count            │ count = N                           │ Multiple instances at [0]..[N-1]     │
│ (not a for loop) │ count.index                         │ Best for: conditional, N-identical   │
└──────────────────┴─────────────────────────────────────┴──────────────────────────────────────┘
```

---

## Clean Up

```bash
terraform destroy -auto-approve
rm -rf ~/tf_works/038_loops
```

```
local_file.site_config["chillbot"]: Destroying...
local_file.site_config["personal"]: Destroying...
local_file.site_config["robochef"]: Destroying...
local_file.team_config["backend"]: Destroying...
local_file.team_config["devops"]: Destroying...
local_file.team_config["frontend"]: Destroying...
random_string.site_token["chillbot"]: Destroying...
random_string.site_token["personal"]: Destroying...
random_string.site_token["robochef"]: Destroying...
random_string.team_token["backend"]: Destroying...
random_string.team_token["devops"]: Destroying...
random_string.team_token["frontend"]: Destroying...
random_string.region_id["ap-south-1"]: Destroying...
random_string.region_id["eu-west-1"]: Destroying...
random_string.region_id["us-east-1"]: Destroying...
...

Destroy complete! Resources: 15 destroyed.
```

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| `for_each = map` | One resource per map key — addressed as `resource["key"]` |
| `each.key` | Current map key ("robochef", "chillbot") |
| `each.value` | Current map value (`{ domain = ..., owner = ... }`) |
| `for_each = toset(list)` | Convert list to set for use with for_each |
| `[for x in list : expr]` | Transform a list into a new list |
| `[for x in list : expr if cond]` | Filter a list |
| `{ for x in list : k => v }` | Build a map from a list |
| `{ for k, v in map : k => expr }` | Transform a map's values |
| `dynamic "block" { for_each content }` | Repeated nested blocks inside a resource |
| `iterator = name` | Rename the dynamic block loop variable |
| `count = bool ? 1 : 0` | Conditional resource creation |
| `for_each` vs `count` | for_each = stable keys; count = index-based (fragile on removal) |

> **Next:** Proceed to **039** for Terraform conditionals and the ternary operator — making infrastructure decisions at plan time.
