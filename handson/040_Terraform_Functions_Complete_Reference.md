# 040 — Terraform Functions: Complete Reference with Examples

**By:** Saravanan Sundaramoorthy
**Environment:** Local + terraform console (no cloud credentials needed)
**Time:** ~20 minutes

---

## Concept

Terraform has **100+ built-in functions** organized into categories. You cannot define your own functions — only use what's built in. Functions are used everywhere: in resource arguments, locals, outputs, and variable defaults.

```
Function categories:
  Numeric      abs, ceil, floor, max, min, pow
  String       lower, upper, format, split, join, replace, substr
  Collection   length, concat, flatten, keys, values, lookup, merge
  Encoding     base64encode, jsonencode, jsondecode, yamlencode
  Filesystem   file, abspath, dirname, basename, pathexpand
  Date/Time    timestamp, formatdate
  Hash/Crypto  md5, sha256, filemd5, bcrypt
  IP Network   cidrsubnet, cidrhost, cidrnetmask
  Type Conv.   tostring, tonumber, tolist, tomap, tobool
```

This lab uses two approaches:
- `terraform console` — interactive REPL for testing functions immediately
- `local_file` resources — functions embedded in actual Terraform code

---

## Prerequisites

Create a fresh project:

```bash
mkdir -p ~/tf_works/040_functions
cd ~/tf_works/040_functions
```

```bash
cat > providers.tf << 'EOF'
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

terraform init
```

Create a sample file that filesystem functions can read:

```bash
cat > sample.txt << 'EOF'
robochef.co
saravanans
EOF
```

---

## Using terraform console

`terraform console` is an interactive REPL where you can test any Terraform expression or function instantly — no apply needed.

```bash
terraform console
```

```
>
```

Type any expression and press Enter. Type `exit` or Ctrl+D to quit.

```
> 2 + 2
4
> upper("robochef")
"ROBOCHEF"
> exit
```

All `terraform console` examples in this lab can be run interactively. The `>` prompt shows what you type; the line below is the result.

---

## Section 1 — Numeric Functions

Numeric functions operate on numbers: integers and floats.

### terraform console — Numeric

```bash
terraform console
```

```
> abs(-5)
5

> abs(5)
5

> ceil(1.2)
2

> ceil(1.9)
2

> ceil(2.0)
2

> floor(1.9)
1

> floor(1.2)
1

> max(3, 5, 2)
5

> max(1, 100, 50, 75)
100

> min(3, 5, 2)
2

> min(1, 100, 50, 75)
1

> pow(2, 10)
1024

> pow(2, 0)
1

> pow(10, 3)
1000
```

```
> exit
```

### Practical use — Numeric in resources

```bash
cat > numeric.tf << 'EOF'
locals {
  base_port    = 8080
  replica_raw  = 2.7
  memory_mb    = -512
}

resource "local_file" "numeric_demo" {
  filename = "/tmp/robochef-numeric.txt"
  content  = <<-EOT
    site=robochef.co
    owner=saravanans

    # abs: make negative memory positive
    memory_mb=${abs(local.memory_mb)}

    # ceil: always round replicas UP
    replicas=${ceil(local.replica_raw)}

    # floor: conservative floor estimate
    replicas_floor=${floor(local.replica_raw)}

    # max/min: clamp port to valid range
    port=${max(local.base_port, 1024)}
    max_port=${min(local.base_port, 65535)}

    # pow: 2^10 = 1024 connections
    max_connections=${pow(2, 10)}
  EOT
}
EOF
```

```bash
terraform apply -auto-approve
cat /tmp/robochef-numeric.txt
```

```
site=robochef.co
owner=saravanans
memory_mb=512
replicas=3
replicas_floor=2
port=8080
max_port=8080
max_connections=1024
```

---

## Section 2 — String Functions

String functions transform, split, join, and format text.

### terraform console — String

```bash
terraform console
```

```
> lower("Robochef.CO")
"robochef.co"

> upper("robochef")
"ROBOCHEF"

> trimspace("  hello world  ")
"hello world"

> split(",", "a,b,c")
tolist([
  "a",
  "b",
  "c",
])

> join("-", ["robochef", "co"])
"robochef-co"

> join(", ", ["alice", "bob", "charlie"])
"alice, bob, charlie"

> format("Site: %s, Port: %d", "robochef.co", 443)
"Site: robochef.co, Port: 443"

> format("User: %s | Env: %s | Replicas: %02d", "saravanans", "prod", 3)
"User: saravanans | Env: prod | Replicas: 03"

> substr("robochef.co", 0, 8)
"robochef"

> substr("robochef.co", 9, 2)
"co"

> replace("chillbot.in", ".in", ".com")
"chillbot.com"

> replace("hello world", " ", "_")
"hello_world"

> startswith("robochef.co", "robo")
true

> startswith("chillbot.in", "robo")
false

> endswith("robochef.co", ".co")
true

> endswith("chillbot.in", ".co")
false
```

```
> exit
```

### Practical use — String in resources

```bash
cat > strings.tf << 'EOF'
variable "site_name" {
  default = "Robochef"
}

variable "domain_suffix" {
  default = ".co"
}

locals {
  site_lower  = lower(var.site_name)
  site_upper  = upper(var.site_name)
  full_domain = format("%s%s", lower(var.site_name), var.domain_suffix)
  slug        = replace(lower(var.site_name), " ", "-")

  tags_raw    = "api,web,database,cache"
  tags_list   = split(",", local.tags_raw)
  tags_joined = join(" | ", local.tags_list)
}

resource "local_file" "string_demo" {
  filename = "/tmp/robochef-strings.txt"
  content  = <<-EOT
    site_lower=${local.site_lower}
    site_upper=${local.site_upper}
    full_domain=${local.full_domain}
    slug=${local.slug}
    tags=${local.tags_joined}
    first_tag=${local.tags_list[0]}
    banner=${format("=== %s (%s) ===", local.full_domain, "saravanans")}
  EOT
}
EOF
```

```bash
terraform apply -auto-approve
cat /tmp/robochef-strings.txt
```

```
site_lower=robochef
site_upper=ROBOCHEF
full_domain=robochef.co
slug=robochef
tags=api | web | database | cache
first_tag=api
banner==== robochef.co (saravanans) ===
```

---

## Section 3 — Collection Functions

Collection functions work on lists, sets, and maps.

### terraform console — Collection

```bash
terraform console
```

```
> length(["a", "b", "c"])
3

> length({a = 1, b = 2})
2

> length("robochef")
8

> concat(["a"], ["b", "c"])
tolist([
  "a",
  "b",
  "c",
])

> concat(["api", "web"], ["db", "cache"], ["queue"])
tolist([
  "api",
  "web",
  "db",
  "cache",
  "queue",
])

> flatten([["a", "b"], ["c"]])
tolist([
  "a",
  "b",
  "c",
])

> flatten([["api", "web"], ["db"], ["cache", "queue"]])
tolist([
  "api",
  "web",
  "db",
  "cache",
  "queue",
])

> keys({site = "robochef.co", owner = "saravanans", env = "prod"})
tolist([
  "env",
  "owner",
  "site",
])

> values({site = "robochef.co", owner = "saravanans", env = "prod"})
tolist([
  "prod",
  "saravanans",
  "robochef.co",
])

> lookup({site = "robochef.co", owner = "saravanans"}, "site", "unknown")
"robochef.co"

> lookup({site = "robochef.co", owner = "saravanans"}, "missing_key", "unknown")
"unknown"

> merge({a = 1}, {b = 2})
{
  "a" = 1
  "b" = 2
}

> merge({site = "robochef.co"}, {owner = "saravanans"}, {env = "prod"})
{
  "env"   = "prod"
  "owner" = "saravanans"
  "site"  = "robochef.co"
}

> toset(["a", "a", "b", "b", "c"])
toset([
  "a",
  "b",
  "c",
])

> contains(["api", "web", "db"], "api")
true

> contains(["api", "web", "db"], "cache")
false

> element(["a", "b", "c"], 1)
"b"

> element(["a", "b", "c"], 0)
"a"

> element(["a", "b", "c"], 5)
"c"

> slice(["a", "b", "c", "d", "e"], 1, 3)
tolist([
  "b",
  "c",
])
```

> `element` wraps around using modulo — `element(list, 5)` on a 3-element list returns index `5 % 3 = 2`.
> `slice(list, start, end)` — `end` is **exclusive** (not included).

```
> exit
```

### Practical use — Collection in resources

```bash
cat > collections.tf << 'EOF'
locals {
  services_a = ["api", "web"]
  services_b = ["database", "cache"]
  all_services = concat(local.services_a, local.services_b)

  nested_cidrs = [["10.0.1.0/24", "10.0.2.0/24"], ["10.0.3.0/24"]]
  flat_cidrs   = flatten(local.nested_cidrs)

  config = {
    site    = "robochef.co"
    owner   = "saravanans"
    env     = "prod"
    version = "2.1"
  }

  defaults = {
    site    = "example.com"
    owner   = "unknown"
    region  = "us-east-1"
  }

  merged_config = merge(local.defaults, local.config)
}

resource "local_file" "collection_demo" {
  filename = "/tmp/robochef-collections.txt"
  content  = <<-EOT
    # concat
    all_services=${join(", ", local.all_services)}
    service_count=${length(local.all_services)}

    # flatten
    all_cidrs=${join(", ", local.flat_cidrs)}

    # keys and values
    config_keys=${join(", ", keys(local.config))}

    # lookup with default
    site=${lookup(local.config, "site", "unknown")}
    missing=${lookup(local.config, "missing", "default-value")}

    # merge (local.config overrides local.defaults)
    merged_site=${local.merged_config["site"]}
    merged_region=${local.merged_config["region"]}

    # toset deduplication
    unique_tags=${join(", ", toset(["api", "web", "api", "db", "web"]))}

    # contains
    has_api=${contains(local.all_services, "api")}
    has_queue=${contains(local.all_services, "queue")}

    # element
    first_service=${element(local.all_services, 0)}
    second_service=${element(local.all_services, 1)}

    # slice
    first_two=${join(", ", slice(local.all_services, 0, 2))}
  EOT
}
EOF
```

```bash
terraform apply -auto-approve
cat /tmp/robochef-collections.txt
```

```
# concat
all_services=api, web, database, cache
service_count=4

# flatten
all_cidrs=10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24

# keys and values
config_keys=env, owner, site, version

# lookup with default
site=robochef.co
missing=default-value

# merge (local.config overrides local.defaults)
merged_site=robochef.co
merged_region=us-east-1

# unique tags
unique_tags=api, db, web

# contains
has_api=true
has_queue=false

# element
first_service=api
second_service=web

# first_two
first_two=api, web
```

---

## Section 4 — Encoding Functions

Encoding functions convert data between formats: base64, JSON, YAML.

### terraform console — Encoding

```bash
terraform console
```

```
> base64encode("robochef.co")
"cm9ib2NoZWYuY28="

> base64decode("cm9ib2NoZWYuY28=")
"robochef.co"

> base64decode(base64encode("robochef.co"))
"robochef.co"

> jsonencode({site = "robochef.co", owner = "saravanans", replicas = 3})
"{\"owner\":\"saravanans\",\"replicas\":3,\"site\":\"robochef.co\"}"

> jsondecode("{\"site\":\"robochef.co\",\"owner\":\"saravanans\"}")
{
  "owner" = "saravanans"
  "site"  = "robochef.co"
}

> jsondecode("{\"site\":\"robochef.co\",\"owner\":\"saravanans\"}").site
"robochef.co"

> yamlencode({site = "robochef.co", owner = "saravanans", replicas = 3})
<<EOT
owner: saravanans
replicas: 3
site: robochef.co

EOT
```

```
> exit
```

### Practical use — Encoding in resources

```bash
cat > encoding.tf << 'EOF'
locals {
  app_config = {
    site     = "robochef.co"
    owner    = "saravanans"
    env      = "prod"
    replicas = 3
    tags     = ["api", "web", "cache"]
  }
}

resource "local_file" "json_config" {
  filename = "/tmp/robochef-config.json"
  content  = jsonencode(local.app_config)
}

resource "local_file" "yaml_config" {
  filename = "/tmp/robochef-config.yaml"
  content  = yamlencode(local.app_config)
}

resource "local_file" "encoded_secret" {
  filename = "/tmp/robochef-secret.txt"
  content  = <<-EOT
    # base64 encoding for config transport
    encoded=${base64encode("robochef.co:saravanans:prod")}
    decoded=${base64decode(base64encode("robochef.co:saravanans:prod"))}

    # json round-trip
    json_site=${jsondecode(jsonencode(local.app_config)).site}
  EOT
}

output "json_config_path" {
  value = local_file.json_config.filename
}
EOF
```

```bash
terraform apply -auto-approve
```

```bash
cat /tmp/robochef-config.json
```

```json
{"env":"prod","owner":"saravanans","replicas":3,"site":"robochef.co","tags":["api","web","cache"]}
```

```bash
cat /tmp/robochef-config.yaml
```

```yaml
env: prod
owner: saravanans
replicas: 3
site: robochef.co
tags:
  - api
  - web
  - cache
```

```bash
cat /tmp/robochef-secret.txt
```

```
# base64 encoding for config transport
encoded=cm9ib2NoZWYuY286c2FyYXZhbmFuczpwcm9k
decoded=robochef.co:saravanans:prod
json_site=robochef.co
```

---

## Section 5 — Filesystem Functions

Filesystem functions read files and resolve paths **at plan time** — before apply runs.

### terraform console — Filesystem

```bash
terraform console
```

```
> abspath("./providers.tf")
"/home/user/tf_works/040_functions/providers.tf"

> pathexpand("~/documents")
"/home/user/documents"

> dirname("/tmp/robochef/logs/app.log")
"/tmp/robochef/logs"

> basename("/tmp/robochef/logs/app.log")
"app.log"

> basename("/tmp/robochef-config.json")
"robochef-config.json"
```

```
> exit
```

> `file("./path")` and `filemd5("./path")` require the file to exist at plan time. They are shown in the resource example below.

### Practical use — Filesystem in resources

```bash
cat > filesystem.tf << 'EOF'
locals {
  sample_content = file("${path.module}/sample.txt")
  sample_hash    = filemd5("${path.module}/sample.txt")
  providers_hash = filemd5("${path.module}/providers.tf")
}

resource "local_file" "filesystem_demo" {
  filename = "/tmp/robochef-filesystem.txt"
  content  = <<-EOT
    # file() reads file content at plan time
    sample_content:
    ${local.sample_content}

    # filemd5() checksums for change detection
    sample_md5=${local.sample_hash}
    providers_md5=${local.providers_hash}

    # path functions
    module_path=${abspath(path.module)}
    sample_basename=${basename("${path.module}/sample.txt")}
    sample_dirname=${dirname("${path.module}/sample.txt")}
  EOT
}
EOF
```

```bash
terraform apply -auto-approve
cat /tmp/robochef-filesystem.txt
```

```
# file() reads file content at plan time
sample_content:
robochef.co
saravanans

# filemd5() checksums for change detection
sample_md5=a3f1c...
providers_md5=b7d2e...

# path functions
module_path=/home/user/tf_works/040_functions
sample_basename=sample.txt
sample_dirname=/home/user/tf_works/040_functions
```

> `path.module` is a special variable — always the directory of the current `.tf` file. Use it instead of hardcoding absolute paths.

> `templatefile(path, vars)` is similar to `file()` but supports variable substitution in the template. Covered in lab 041.

---

## Section 6 — Date and Time Functions

Date functions generate and format timestamps.

### terraform console — Date/Time

```bash
terraform console
```

```
> timestamp()
"2026-05-21T10:30:00Z"

> formatdate("YYYY-MM-DD", timestamp())
"2026-05-21"

> formatdate("DD/MM/YYYY hh:mm:ss", timestamp())
"21/05/2026 10:30:00"

> formatdate("YYYYMMDDhhmmss", timestamp())
"20260521103000"
```

```
> exit
```

> `timestamp()` returns the current UTC time in RFC 3339 format. It re-evaluates on every plan — useful for build timestamps, but will always show a diff if used in resource content directly.

### Practical use — Date/Time in resources

```bash
cat > datetime.tf << 'EOF'
locals {
  build_timestamp = timestamp()
  build_date      = formatdate("YYYY-MM-DD", local.build_timestamp)
  build_datetime  = formatdate("YYYY-MM-DD hh:mm:ss", local.build_timestamp)
  build_tag       = formatdate("YYYYMMDDhhmmss", local.build_timestamp)
}

resource "local_file" "build_info" {
  filename = "/tmp/robochef-build.txt"
  content  = <<-EOT
    site=robochef.co
    owner=saravanans
    build_timestamp=${local.build_timestamp}
    build_date=${local.build_date}
    build_datetime=${local.build_datetime}
    build_tag=${local.build_tag}
  EOT
}
EOF
```

```bash
terraform apply -auto-approve
cat /tmp/robochef-build.txt
```

```
site=robochef.co
owner=saravanans
build_timestamp=2026-05-21T10:30:00Z
build_date=2026-05-21
build_datetime=2026-05-21 10:30:00
build_tag=20260521103000
```

> Every `terraform apply` will update the timestamp, causing `local_file.build_info` to show as changed. This is expected — timestamp() is not stable.

---

## Section 7 — Hash and Crypto Functions

Hash functions produce deterministic fingerprints. Useful for checksums, unique IDs, and password hashing.

### terraform console — Hash/Crypto

```bash
terraform console
```

```
> md5("robochef.co")
"2e5a4e7c..."

> sha256("robochef.co")
"3b4c7d8e..."

> sha256("saravanans")
"9f2a1b3c..."
```

```
> exit
```

> `bcrypt()` and `filemd5()` require a file argument — shown in the resource example.

### Practical use — Hash/Crypto in resources

```bash
cat > hashing.tf << 'EOF'
locals {
  site_md5    = md5("robochef.co")
  site_sha256 = sha256("robochef.co")
  owner_sha256 = sha256("saravanans")
  file_hash   = filemd5("${path.module}/sample.txt")
}

resource "local_file" "hash_demo" {
  filename = "/tmp/robochef-hashes.txt"
  content  = <<-EOT
    site=robochef.co
    owner=saravanans

    # md5 (fast, not crypto-safe — use for checksums only)
    site_md5=${local.site_md5}

    # sha256 (stronger — use for integrity checks)
    site_sha256=${local.site_sha256}
    owner_sha256=${local.owner_sha256}

    # filemd5 — hash a file for change detection
    sample_file_md5=${local.file_hash}

    # unique ID from hash (first 8 chars of md5)
    deploy_id=${substr(local.site_md5, 0, 8)}
  EOT
}

resource "local_file" "htpasswd" {
  filename = "/tmp/robochef-htpasswd.txt"
  content  = "saravanans:${bcrypt("robochef-secret-password")}\n"
}
EOF
```

```bash
terraform apply -auto-approve
cat /tmp/robochef-hashes.txt
```

```
site=robochef.co
owner=saravanans

# md5 (fast, not crypto-safe — use for checksums only)
site_md5=2e5a4e7c9b1f3a8d...

# sha256 (stronger — use for integrity checks)
site_sha256=3b4c7d8e2f6a1c9b...
owner_sha256=9f2a1b3c7e4d8f1a...

# filemd5 — hash a file for change detection
sample_file_md5=a3f1c8b2...

# unique ID from hash (first 8 chars of md5)
deploy_id=2e5a4e7c
```

```bash
cat /tmp/robochef-htpasswd.txt
```

```
saravanans:$2a$10$...bcrypt-hash-here...
```

> `bcrypt()` produces a different hash each time (salted) — `local_file.htpasswd` will show as changed on every plan. Use keepers or store the result in a `random_password` resource if you need stability.

---

## Section 8 — IP Network Functions

Network functions calculate CIDR subnets and host addresses. Essential for VPC and networking configurations.

### terraform console — IP Network

```bash
terraform console
```

```
> cidrsubnet("10.0.0.0/16", 8, 1)
"10.0.1.0/24"

> cidrsubnet("10.0.0.0/16", 8, 2)
"10.0.2.0/24"

> cidrsubnet("10.0.0.0/16", 8, 255)
"10.0.255.0/24"

> cidrhost("10.0.1.0/24", 5)
"10.0.1.5"

> cidrhost("10.0.1.0/24", 1)
"10.0.1.1"

> cidrhost("10.0.1.0/24", 254)
"10.0.1.254"

> cidrnetmask("10.0.1.0/24")
"255.255.255.0"

> cidrnetmask("10.0.0.0/16")
"255.255.0.0"

> cidrnetmask("10.0.0.0/8")
"255.0.0.0"
```

```
> exit
```

### Understanding cidrsubnet

```
cidrsubnet("10.0.0.0/16", 8, 1)
            │              │  │
            │              │  └─ subnet index (0=first, 1=second...)
            │              └─ bits to add (16 + 8 = /24)
            └─ base CIDR block

Result: "10.0.1.0/24"
  base:    10.0.0.0/16   (16-bit network)
  +8 bits: 10.0.1.0/24   (24-bit network, subnet index 1)
```

### Practical use — IP Network in resources

```bash
cat > networking.tf << 'EOF'
locals {
  vpc_cidr = "10.0.0.0/16"

  subnets = {
    public_1  = cidrsubnet(local.vpc_cidr, 8, 1)
    public_2  = cidrsubnet(local.vpc_cidr, 8, 2)
    private_1 = cidrsubnet(local.vpc_cidr, 8, 10)
    private_2 = cidrsubnet(local.vpc_cidr, 8, 11)
    db_1      = cidrsubnet(local.vpc_cidr, 8, 20)
  }

  gateway_ip   = cidrhost(local.subnets["public_1"], 1)
  lb_ip        = cidrhost(local.subnets["public_1"], 5)
  app_ip       = cidrhost(local.subnets["private_1"], 10)
  db_ip        = cidrhost(local.subnets["db_1"], 10)
}

resource "local_file" "network_plan" {
  filename = "/tmp/robochef-network.txt"
  content  = <<-EOT
    site=robochef.co
    owner=saravanans

    # VPC
    vpc_cidr=${local.vpc_cidr}
    vpc_netmask=${cidrnetmask(local.vpc_cidr)}

    # Subnets (auto-calculated from VPC CIDR)
    public_1=${local.subnets["public_1"]}
    public_2=${local.subnets["public_2"]}
    private_1=${local.subnets["private_1"]}
    private_2=${local.subnets["private_2"]}
    db_1=${local.subnets["db_1"]}

    # Host addresses
    gateway=${local.gateway_ip}
    load_balancer=${local.lb_ip}
    app_server=${local.app_ip}
    db_server=${local.db_ip}
    subnet_mask=${cidrnetmask(local.subnets["public_1"])}
  EOT
}
EOF
```

```bash
terraform apply -auto-approve
cat /tmp/robochef-network.txt
```

```
site=robochef.co
owner=saravanans

# VPC
vpc_cidr=10.0.0.0/16
vpc_netmask=255.255.0.0

# Subnets (auto-calculated from VPC CIDR)
public_1=10.0.1.0/24
public_2=10.0.2.0/24
private_1=10.0.10.0/24
private_2=10.0.11.0/24
db_1=10.0.20.0/24

# Host addresses
gateway=10.0.1.1
load_balancer=10.0.1.5
app_server=10.0.10.10
db_server=10.0.20.10
subnet_mask=255.255.255.0
```

> This pattern is common in AWS/GCP/Azure modules — define one `vpc_cidr` variable and derive all subnet CIDRs mathematically with `cidrsubnet`. No hardcoding, no miscalculations.

---

## Section 9 — Type Conversion Functions

Type conversion functions explicitly cast values between Terraform types.

### terraform console — Type Conversion

```bash
terraform console
```

```
> tostring(42)
"42"

> tostring(3.14)
"3.14"

> tostring(true)
"true"

> tonumber("42")
42

> tonumber("3.14")
3.14

> tobool("true")
true

> tobool("false")
false

> tolist(toset(["a", "b", "c"]))
tolist([
  "a",
  "b",
  "c",
])

> toset(["a", "a", "b"])
toset([
  "a",
  "b",
])

> tomap({a = "1", b = "2"})
{
  "a" = "1"
  "b" = "2"
}
```

```
> exit
```

### When type conversion is needed

```
Terraform is mostly type-safe — conversions happen automatically in many cases.
Explicit conversion is needed when:

  1. A resource attribute expects a specific type
     length = tonumber(var.length_string)

  2. for_each requires a set or map
     for_each = toset(var.environments)

  3. Output needs a consistent type
     value = tostring(local.count)

  4. JSON data comes back as wrong type
     replicas = tonumber(jsondecode(data.file.config).replicas)
```

### Practical use — Type Conversion in resources

```bash
cat > types.tf << 'EOF'
variable "replica_count_str" {
  description = "Replica count as string (simulating external data source)"
  type        = string
  default     = "3"
}

variable "debug_enabled_str" {
  description = "Boolean flag as string"
  type        = string
  default     = "true"
}

variable "env_list" {
  description = "Environments as list (may have duplicates)"
  type        = list(string)
  default     = ["dev", "staging", "prod", "staging", "dev"]
}

locals {
  replica_count  = tonumber(var.replica_count_str)
  debug_enabled  = tobool(var.debug_enabled_str)
  unique_envs    = toset(var.env_list)
  count_as_str   = tostring(local.replica_count)
}

resource "local_file" "types_demo" {
  filename = "/tmp/robochef-types.txt"
  content  = <<-EOT
    site=robochef.co
    owner=saravanans

    # tonumber: string -> number for arithmetic
    replica_count=${local.replica_count}
    replicas_doubled=${local.replica_count * 2}

    # tobool: string -> bool for conditionals
    debug_enabled=${local.debug_enabled}

    # toset: deduplicates list
    unique_envs=${join(", ", local.unique_envs)}
    original_count=${length(var.env_list)}
    unique_count=${length(local.unique_envs)}

    # tostring: number -> string for concatenation
    count_label=replica-count-${local.count_as_str}
  EOT
}

resource "random_string" "tokens" {
  for_each = toset(var.env_list)
  length   = 16
  special  = false
}

output "token_keys" {
  value = keys(random_string.tokens)
}
EOF
```

```bash
terraform apply -auto-approve
cat /tmp/robochef-types.txt
```

```
site=robochef.co
owner=saravanans

# tonumber: string -> number for arithmetic
replica_count=3
replicas_doubled=6

# tobool: string -> bool for conditionals
debug_enabled=true

# toset: deduplicates list
unique_envs=dev, prod, staging
original_count=5
unique_count=3

# count_label
count_label=replica-count-3
```

```bash
terraform output token_keys
```

```
tolist([
  "dev",
  "prod",
  "staging",
])
```

> `toset(var.env_list)` deduplicated the 5-item list (`dev, staging, prod, staging, dev`) to 3 unique items. `for_each` received only 3 keys — only 3 `random_string` resources were created.

---

## Combining Functions

Functions are most powerful when **chained and combined** in locals.

```bash
cat > combined.tf << 'EOF'
locals {
  raw_sites = "Robochef.CO, Chillbot.IN, MyApp.IO"

  sites = [
    for s in split(",", local.raw_sites) :
    trimspace(lower(s))
  ]

  site_slugs = {
    for s in local.sites :
    s => replace(replace(s, ".", "-"), " ", "-")
  }

  site_summary = join("\n", [
    for s in local.sites :
    format("  %-20s → %s", s, local.site_slugs[s])
  ])

  config_json = jsonencode({
    owner     = "saravanans"
    sites     = local.sites
    slugs     = local.site_slugs
    generated = formatdate("YYYY-MM-DD", timestamp())
    checksum  = md5(join(",", local.sites))
  })
}

resource "local_file" "combined_demo" {
  filename = "/tmp/robochef-combined.txt"
  content  = <<-EOT
    owner=saravanans
    generated=${formatdate("YYYY-MM-DD", timestamp())}

    # raw input → cleaned list
    raw=${local.raw_sites}
    sites=${join(", ", local.sites)}
    site_count=${length(local.sites)}

    # slug map
    ${local.site_summary}

    # md5 fingerprint of site list
    checksum=${md5(join(",", local.sites))}

    # full config as JSON
    ${local.config_json}
  EOT
}
EOF
```

```bash
terraform apply -auto-approve
cat /tmp/robochef-combined.txt
```

```
owner=saravanans
generated=2026-05-21

# raw input -> cleaned list
raw=Robochef.CO, Chillbot.IN, MyApp.IO
sites=robochef.co, chillbot.in, myapp.io
site_count=3

# slug map
  robochef.co          -> robochef-co
  chillbot.in          -> chillbot-in
  myapp.io             -> myapp-io

# md5 fingerprint of site list
checksum=8f2a...

# full config as JSON
{"checksum":"8f2a...","generated":"2026-05-21","owner":"saravanans","sites":["robochef.co","chillbot.in","myapp.io"],"slugs":{"chillbot.in":"chillbot-in","myapp.io":"myapp-io","robochef.co":"robochef-co"}}
```

---

## Quick Reference

### terraform console cheatsheet

```bash
terraform console          # open REPL
# type any expression, press Enter
# Ctrl+D or type exit to quit
```

### Function categories at a glance

```
NUMERIC
  abs(n)                          absolute value
  ceil(n)  floor(n)               round up / down
  max(a,b,c)  min(a,b,c)          largest / smallest
  pow(base, exp)                  exponentiation

STRING
  lower(s)  upper(s)              case conversion
  trimspace(s)                    strip whitespace
  split(sep, s)                   string → list
  join(sep, list)                 list → string
  format(fmt, args...)            printf-style
  substr(s, offset, len)          substring
  replace(s, old, new)            string replace
  startswith(s, prefix)           prefix check
  endswith(s, suffix)             suffix check

COLLECTION
  length(v)                       count items
  concat(list, list...)           merge lists
  flatten(list_of_lists)          one level deep
  keys(map)  values(map)          map keys/values
  lookup(map, key, default)       safe map access
  merge(map, map...)              merge maps
  toset(list)                     deduplicate
  contains(list, value)           membership test
  element(list, index)            get by index (wraps)
  slice(list, start, end)         sublist (end exclusive)

ENCODING
  base64encode(s)  base64decode(s)
  jsonencode(v)    jsondecode(s)
  yamlencode(v)

FILESYSTEM
  file(path)                      read file at plan time
  filemd5(path)                   md5 of file
  abspath(path)                   absolute path
  pathexpand(path)                expand ~ to home dir
  dirname(path)                   directory part
  basename(path)                  filename part

DATE/TIME
  timestamp()                     current RFC 3339 UTC
  formatdate(format, timestamp)   format a timestamp

HASH/CRYPTO
  md5(s)                          MD5 hex digest
  sha256(s)                       SHA-256 hex digest
  filemd5(path)                   MD5 of file content
  bcrypt(s)                       bcrypt hash (for htpasswd)

IP NETWORK
  cidrsubnet(cidr, bits, idx)     calculate subnet CIDR
  cidrhost(cidr, hostnum)         IP address in subnet
  cidrnetmask(cidr)               subnet mask string

TYPE CONVERSION
  tostring(v)                     any → string
  tonumber(s)                     string → number
  tobool(s)                       string → bool
  tolist(v)                       convert to list
  toset(v)                        convert to set
  tomap(v)                        convert to map
```

---

## Clean Up

```bash
terraform destroy -auto-approve
cd ~
rm -rf ~/tf_works/040_functions
rm -rf .terraform
```

---

## Summary

| Category | Key Functions |
|----------|--------------|
| Numeric | `abs`, `ceil`, `floor`, `max`, `min`, `pow` |
| String | `lower`, `upper`, `format`, `split`, `join`, `replace`, `substr` |
| Collection | `length`, `concat`, `flatten`, `keys`, `lookup`, `merge`, `toset` |
| Encoding | `base64encode`, `jsonencode`, `jsondecode`, `yamlencode` |
| Filesystem | `file`, `filemd5`, `abspath`, `basename`, `dirname` |
| Date/Time | `timestamp`, `formatdate` |
| Hash/Crypto | `md5`, `sha256`, `filemd5`, `bcrypt` |
| IP Network | `cidrsubnet`, `cidrhost`, `cidrnetmask` |
| Type Conv. | `tostring`, `tonumber`, `tobool`, `toset`, `tolist` |

> **Next:** Proceed to **041** for `templatefile()` — rendering dynamic configuration files with Terraform templates.
