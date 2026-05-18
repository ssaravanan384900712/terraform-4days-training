# Hands-On 3.3 --- Terraform Functions

**File:** `terraform console` interactive session, `main.tf`

---

## Concept

Terraform includes a rich set of built-in functions you can call from expressions. Functions transform and combine values --- you **cannot** define custom functions (only modules provide reuse).

```
Input Value(s)  ---->  function()  ---->  Output Value
"hello world"   ---->  upper()    ---->  "HELLO WORLD"
[1, 2, 3]       ---->  length()   ---->  3
"10.0.0.0/16"   ---->  cidrsubnet()-->  "10.0.1.0/24"
```

### Using `terraform console`

The fastest way to learn functions is the interactive console:

```bash
$ terraform console
> upper("hello")
"HELLO"
> max(5, 12, 3)
12
> exit
```

> **Tip:** You can pipe expressions: `echo 'upper("hello")' | terraform console`

---

## 1. Numeric Functions

| Function | Purpose | Example |
|----------|---------|---------|
| `abs(n)` | Absolute value | `abs(-5)` = `5` |
| `ceil(n)` | Round up | `ceil(4.2)` = `5` |
| `floor(n)` | Round down | `floor(4.9)` = `4` |
| `max(n...)` | Largest value | `max(3, 1, 5)` = `5` |
| `min(n...)` | Smallest value | `min(3, 1, 5)` = `1` |
| `pow(b, e)` | Exponentiation | `pow(2, 10)` = `1024` |
| `signum(n)` | Sign (-1, 0, 1) | `signum(-42)` = `-1` |

### Console Examples

```
> abs(-15)
15

> ceil(4.1)
5

> floor(4.9)
4

> max(10, 25, 3, 42, 7)
42

> min(10, 25, 3, 42, 7)
3

> pow(2, 8)
256

> signum(-99)
-1

> signum(0)
0

> signum(42)
1
```

### Practical Use

```hcl
# Calculate number of subnets needed (round up)
locals {
  instances_per_subnet = 50
  total_instances      = 120
  subnets_needed       = ceil(local.total_instances / local.instances_per_subnet)
  # Result: ceil(2.4) = 3
}
```

---

## 2. String Functions

| Function | Purpose |
|----------|---------|
| `lower(s)` | Lowercase |
| `upper(s)` | Uppercase |
| `title(s)` | Title Case |
| `trim(s, chars)` | Strip characters from both ends |
| `trimspace(s)` | Strip whitespace |
| `trimprefix(s, prefix)` | Remove prefix |
| `trimsuffix(s, suffix)` | Remove suffix |
| `split(sep, s)` | String to list |
| `join(sep, list)` | List to string |
| `format(spec, vals...)` | Printf-style formatting |
| `formatlist(spec, list)` | Format each element |
| `replace(s, find, repl)` | String replacement |
| `substr(s, offset, len)` | Substring |
| `regex(pattern, s)` | Regex match |
| `regexall(pattern, s)` | All regex matches |
| `startswith(s, prefix)` | Check prefix |
| `endswith(s, suffix)` | Check suffix |
| `strcontains(s, sub)` | Check contains |
| `chomp(s)` | Remove trailing newline |

### Console Examples

```
> lower("Terraform ROCKS")
"terraform rocks"

> upper("hello world")
"HELLO WORLD"

> title("hello world")
"Hello World"

> trim("??hello??", "?")
"hello"

> trimspace("  hello  ")
"hello"

> trimprefix("arn:aws:s3:::my-bucket", "arn:aws:s3:::")
"my-bucket"

> trimsuffix("web-server.tf", ".tf")
"web-server"

> split(",", "a,b,c,d")
tolist(["a", "b", "c", "d"])

> join("-", ["web", "server", "01"])
"web-server-01"

> format("Hello, %s! You have %d items.", "Alice", 5)
"Hello, Alice! You have 5 items."

> format("%-20s %s", "Name:", "web-server")
"Name:                web-server"

> formatlist("server-%s", ["a", "b", "c"])
tolist(["server-a", "server-b", "server-c"])

> replace("hello world", "world", "terraform")
"hello terraform"

> replace("10.0.0.0/16", "/", "-")
"10.0.0.0-16"

> substr("hello world", 0, 5)
"hello"

> substr("hello world", 6, -1)
"world"

> regex("[a-z]+", "123abc456")
"abc"

> regexall("[0-9]+", "port 80 and port 443")
tolist(["80", "443"])

> startswith("terraform", "terra")
true

> endswith("main.tf", ".tf")
true

> strcontains("hello world", "world")
true
```

### Practical Use

```hcl
# Generate resource names
locals {
  name_prefix = format("%s-%s", var.project, var.environment)
  # "acme-prod"

  subnet_names = formatlist("%s-subnet-%s", local.name_prefix, ["a", "b", "c"])
  # ["acme-prod-subnet-a", "acme-prod-subnet-b", "acme-prod-subnet-c"]

  # Parse an S3 ARN
  bucket_name = trimprefix("arn:aws:s3:::my-logs-bucket", "arn:aws:s3:::")
  # "my-logs-bucket"
}
```

---

## 3. Collection Functions

| Function | Purpose |
|----------|---------|
| `length(col)` | Number of elements |
| `concat(list1, list2)` | Join lists |
| `flatten(list)` | Flatten nested lists |
| `keys(map)` | Map keys as list |
| `values(map)` | Map values as list |
| `lookup(map, key, default)` | Safe map access |
| `merge(map1, map2)` | Combine maps |
| `contains(list, val)` | Check membership |
| `distinct(list)` | Remove duplicates |
| `sort(list)` | Sort strings |
| `reverse(list)` | Reverse list |
| `zipmap(keys, values)` | Two lists to map |
| `element(list, idx)` | Index with wrapping |
| `index(list, val)` | Find index of value |
| `slice(list, start, end)` | Sub-list |
| `compact(list)` | Remove empty strings |
| `coalesce(vals...)` | First non-null/empty |
| `coalescelist(lists...)` | First non-empty list |
| `range(max)` | Generate number list |
| `chunklist(list, size)` | Split into chunks |
| `setproduct(sets...)` | Cartesian product |
| `setunion(sets...)` | Set union |
| `setintersection(s...)` | Set intersection |
| `setsubtract(a, b)` | Set difference |
| `one(list)` | Extract single element or null |
| `sum(list)` | Sum of numbers |
| `alltrue(list)` | All elements true? |
| `anytrue(list)` | Any element true? |

### Console Examples

```
> length([1, 2, 3, 4, 5])
5

> length({a = 1, b = 2})
2

> length("hello")
5

> concat(["a", "b"], ["c", "d"])
tolist(["a", "b", "c", "d"])

> flatten([["a", "b"], ["c"], ["d", "e"]])
tolist(["a", "b", "c", "d", "e"])

> flatten([["vpc-1", ["subnet-a", "subnet-b"]], ["vpc-2", ["subnet-c"]]])
tolist(["vpc-1", "subnet-a", "subnet-b", "vpc-2", "subnet-c"])

> keys({name = "web", env = "prod", region = "us-east-1"})
tolist(["env", "name", "region"])

> values({name = "web", env = "prod", region = "us-east-1"})
tolist(["prod", "web", "us-east-1"])

> lookup({dev = "t3.micro", prod = "t3.large"}, "prod", "t3.medium")
"t3.large"

> lookup({dev = "t3.micro", prod = "t3.large"}, "staging", "t3.medium")
"t3.medium"

> merge({a = 1, b = 2}, {b = 3, c = 4})
tomap({"a" = 1, "b" = 3, "c" = 4})

> contains(["us-east-1", "us-west-2", "eu-west-1"], "us-west-2")
true

> contains(["us-east-1", "us-west-2", "eu-west-1"], "ap-south-1")
false

> distinct(["a", "b", "a", "c", "b"])
tolist(["a", "b", "c"])

> sort(["banana", "apple", "cherry"])
tolist(["apple", "banana", "cherry"])

> reverse([1, 2, 3, 4, 5])
[5, 4, 3, 2, 1]

> zipmap(["name", "env"], ["web-server", "production"])
tomap({"env" = "production", "name" = "web-server"})

> element(["a", "b", "c"], 4)
"b"

> range(5)
tolist([0, 1, 2, 3, 4])

> range(1, 6)
tolist([1, 2, 3, 4, 5])

> range(0, 10, 2)
tolist([0, 2, 4, 6, 8])

> compact(["a", "", "b", "", "c"])
tolist(["a", "b", "c"])

> coalesce("", "", "hello", "world")
"hello"

> slice(["a", "b", "c", "d", "e"], 1, 4)
tolist(["b", "c", "d"])

> chunklist(["a", "b", "c", "d", "e"], 2)
tolist([tolist(["a", "b"]), tolist(["c", "d"]), tolist(["e"])])

> setproduct(["web", "api"], ["dev", "prod"])
tolist([tolist(["web", "dev"]), tolist(["web", "prod"]), tolist(["api", "dev"]), tolist(["api", "prod"])])

> sum([10, 20, 30])
60

> alltrue([true, true, true])
true

> alltrue([true, false, true])
false

> anytrue([false, false, true])
true
```

### Practical Use

```hcl
# Instance type lookup map
variable "environment" {
  default = "dev"
}

locals {
  instance_types = {
    dev     = "t3.micro"
    staging = "t3.small"
    prod    = "t3.large"
  }

  instance_type = lookup(local.instance_types, var.environment, "t3.micro")

  # Merge default tags with custom tags
  default_tags = { ManagedBy = "terraform", Environment = var.environment }
  custom_tags  = { Application = "web", Team = "platform" }
  all_tags     = merge(local.default_tags, local.custom_tags)

  # Create AZ-to-subnet map
  azs     = ["us-east-1a", "us-east-1b", "us-east-1c"]
  cidrs   = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  az_cidr = zipmap(local.azs, local.cidrs)
  # {"us-east-1a" = "10.0.1.0/24", ...}
}
```

---

## 4. Encoding Functions

| Function | Purpose |
|----------|---------|
| `base64encode(s)` | Encode to base64 |
| `base64decode(s)` | Decode from base64 |
| `jsonencode(val)` | Value to JSON string |
| `jsondecode(s)` | JSON string to value |
| `yamlencode(val)` | Value to YAML string |
| `yamldecode(s)` | YAML string to value |
| `urlencode(s)` | URL percent-encoding |
| `csvdecode(s)` | CSV to list of maps |
| `textencodebase64(s, enc)` | Encode text with charset |
| `textdecodebase64(s, enc)` | Decode text with charset |

### Console Examples

```
> base64encode("Hello Terraform")
"SGVsbG8gVGVycmFmb3Jt"

> base64decode("SGVsbG8gVGVycmFmb3Jt")
"Hello Terraform"

> jsonencode({name = "web", ports = [80, 443]})
"{\"name\":\"web\",\"ports\":[80,443]}"

> jsondecode("{\"name\":\"web\",\"port\":80}")
{"name" = "web", "port" = 80}

> yamlencode({name = "web", replicas = 3})
"\"name\": \"web\"\n\"replicas\": 3\n"

> urlencode("hello world/path")
"hello+world%2Fpath"

> csvdecode("name,size\nweb,t3.micro\napi,t3.small")
tolist([
  {"name" = "web", "size" = "t3.micro"},
  {"name" = "api", "size" = "t3.small"},
])
```

### Practical Use

```hcl
# Encode user data for EC2 launch
resource "aws_instance" "web" {
  ami           = data.aws_ami.latest.id
  instance_type = "t3.micro"

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    db_host = aws_db_instance.main.endpoint
  }))
}

# IAM policy as JSON
resource "aws_iam_policy" "s3_read" {
  name = "s3-read-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"]
    }]
  })
}
```

---

## 5. Filesystem Functions

| Function | Purpose |
|----------|---------|
| `file(path)` | Read file as string |
| `fileexists(path)` | Check if file exists |
| `templatefile(path, vars)` | Render template file |
| `abspath(path)` | Absolute path |
| `basename(path)` | Filename from path |
| `dirname(path)` | Directory from path |
| `pathexpand(path)` | Expand ~ in path |
| `filebase64(path)` | Read file as base64 |
| `fileset(path, pattern)` | Glob match files |
| `filemd5(path)` | MD5 of file contents |
| `filesha256(path)` | SHA256 of file contents |

### Console Examples

```
> basename("/home/user/project/main.tf")
"main.tf"

> dirname("/home/user/project/main.tf")
"/home/user/project"

> pathexpand("~/.ssh/id_rsa.pub")
"/home/user/.ssh/id_rsa.pub"

> abspath(".")
"/home/user/terraform-project"
```

### Practical Use

```hcl
# Read SSH public key
resource "aws_key_pair" "deploy" {
  key_name   = "deploy"
  public_key = file("~/.ssh/id_rsa.pub")
}

# Template rendering with variables
# user_data.sh.tpl:
#   #!/bin/bash
#   echo "DB_HOST=${db_host}" >> /etc/environment
#   echo "APP_PORT=${app_port}" >> /etc/environment

resource "aws_instance" "app" {
  ami           = "ami-0abcdef1234567890"
  instance_type = "t3.micro"

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    db_host  = "mydb.cluster-abc.us-east-1.rds.amazonaws.com"
    app_port = 8080
  })
}

# Upload all files in a directory to S3
resource "aws_s3_object" "website_files" {
  for_each = fileset("${path.module}/website", "**/*")

  bucket = aws_s3_bucket.website.id
  key    = each.value
  source = "${path.module}/website/${each.value}"
  etag   = filemd5("${path.module}/website/${each.value}")
}
```

---

## 6. Date/Time Functions

| Function | Purpose |
|----------|---------|
| `timestamp()` | Current UTC time in RFC3339 |
| `formatdate(spec, time)` | Format a timestamp |
| `timeadd(time, duration)` | Add duration to time |
| `timecmp(a, b)` | Compare two timestamps |
| `plantimestamp()` | Time when plan started |

### Console Examples

```
> timestamp()
"2024-03-15T14:30:00Z"

> formatdate("YYYY-MM-DD", timestamp())
"2024-03-15"

> formatdate("DD MMM YYYY hh:mm", timestamp())
"15 Mar 2024 14:30"

> formatdate("EEE", timestamp())
"Fri"

> timeadd(timestamp(), "24h")
"2024-03-16T14:30:00Z"

> timeadd(timestamp(), "720h")
"2024-04-14T14:30:00Z"

> timecmp("2024-01-01T00:00:00Z", "2024-06-01T00:00:00Z")
-1
```

### Practical Use

```hcl
locals {
  deploy_time     = timestamp()
  expiry_date     = timeadd(timestamp(), "2160h")  # 90 days
  deploy_date_tag = formatdate("YYYY-MM-DD", timestamp())
}

resource "aws_instance" "temp" {
  ami           = "ami-0abcdef1234567890"
  instance_type = "t3.micro"

  tags = {
    Name       = "temp-server"
    DeployedAt = local.deploy_time
    ExpiresAt  = local.expiry_date
  }
}
```

> **Warning:** `timestamp()` returns the current time, so it changes every plan. Use `plantimestamp()` if you need the time to stay consistent within a single plan/apply cycle. Consider using `ignore_changes` on tags that use timestamp to avoid constant diffs.

---

## 7. Hash and Crypto Functions

| Function | Purpose |
|----------|---------|
| `md5(s)` | MD5 hash |
| `sha1(s)` | SHA-1 hash |
| `sha256(s)` | SHA-256 hash |
| `sha512(s)` | SHA-512 hash |
| `bcrypt(s)` | Bcrypt hash (password) |
| `uuid()` | Random UUID |
| `uuidv5(ns, name)` | Deterministic UUID v5 |
| `base64sha256(s)` | Base64-encoded SHA-256 |
| `base64sha512(s)` | Base64-encoded SHA-512 |

### Console Examples

```
> md5("hello")
"5d41402abc4b2a76b9719d911017c592"

> sha256("hello")
"2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

> substr(sha256("my-unique-resource"), 0, 8)
"2cf24dba"

> uuid()
"a1b2c3d4-e5f6-7890-abcd-ef1234567890"

> base64sha256("hello")
"LPJNul+wow4m6DsqxbninhsWHowMvPe4WfBitjMo6Oo="
```

### Practical Use

```hcl
# Unique suffix for globally unique names
resource "aws_s3_bucket" "data" {
  bucket = "myapp-data-${substr(md5(var.project_name), 0, 8)}"
}

# Lambda deployment hash (detect code changes)
resource "aws_lambda_function" "processor" {
  filename         = "lambda.zip"
  function_name    = "data-processor"
  handler          = "index.handler"
  runtime          = "python3.12"
  source_code_hash = filebase64sha256("lambda.zip")
  role             = aws_iam_role.lambda.arn
}
```

---

## 8. IP Network Functions

| Function | Purpose |
|----------|---------|
| `cidrsubnet(prefix, newbits, netnum)` | Calculate subnet CIDR |
| `cidrhost(prefix, hostnum)` | Calculate host IP |
| `cidrnetmask(prefix)` | Get netmask from CIDR |
| `cidrsubnets(prefix, newbits...)` | Multiple subnets at once |

### Console Examples

```
> cidrsubnet("10.0.0.0/16", 8, 0)
"10.0.0.0/24"

> cidrsubnet("10.0.0.0/16", 8, 1)
"10.0.1.0/24"

> cidrsubnet("10.0.0.0/16", 8, 2)
"10.0.2.0/24"

> cidrsubnet("10.0.0.0/16", 8, 255)
"10.0.255.0/24"

> cidrsubnet("10.0.0.0/16", 4, 1)
"10.0.16.0/20"

> cidrhost("10.0.1.0/24", 5)
"10.0.1.5"

> cidrhost("10.0.1.0/24", 254)
"10.0.1.254"

> cidrnetmask("10.0.0.0/16")
"255.255.0.0"

> cidrnetmask("10.0.0.0/24")
"255.255.255.0"

> cidrsubnets("10.0.0.0/16", 8, 8, 8, 4)
tolist(["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24", "10.0.16.0/20"])
```

### How cidrsubnet Works

```
cidrsubnet(prefix, newbits, netnum)

prefix:  "10.0.0.0/16"   (base CIDR)
newbits: 8                (add 8 bits to the prefix length: /16 + 8 = /24)
netnum:  1                (the 2nd subnet in that range)

10.0.0.0/16
  ├── 10.0.0.0/24   (netnum = 0)
  ├── 10.0.1.0/24   (netnum = 1)  <-- result
  ├── 10.0.2.0/24   (netnum = 2)
  └── ... up to 10.0.255.0/24 (netnum = 255)
```

### Practical Use

```hcl
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

locals {
  azs = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
}

# Public subnets: 10.0.0.0/24, 10.0.1.0/24, 10.0.2.0/24
resource "aws_subnet" "public" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = local.azs[count.index]

  tags = {
    Name = "public-${local.azs[count.index]}"
  }
}

# Private subnets: 10.0.10.0/24, 10.0.11.0/24, 10.0.12.0/24
resource "aws_subnet" "private" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = local.azs[count.index]

  tags = {
    Name = "private-${local.azs[count.index]}"
  }
}
```

---

## 9. Type Conversion Functions

| Function | Purpose |
|----------|---------|
| `tostring(val)` | Convert to string |
| `tonumber(val)` | Convert to number |
| `tobool(val)` | Convert to bool |
| `tolist(val)` | Convert to list |
| `toset(val)` | Convert to set |
| `tomap(val)` | Convert to map |
| `try(expr, fallback)` | Try expression, return fallback on error |
| `can(expr)` | Test if expression is valid |
| `type(val)` | Return type of value |
| `nonsensitive(val)` | Remove sensitive marking |
| `sensitive(val)` | Mark as sensitive |

### Console Examples

```
> tostring(42)
"42"

> tonumber("42")
42

> tobool("true")
true

> tolist(toset(["b", "a", "c"]))
tolist(["a", "b", "c"])

> toset(["a", "b", "a", "c"])
toset(["a", "b", "c"])

> try(tonumber("not-a-number"), 0)
0

> try(tonumber("42"), 0)
42

> can(tonumber("42"))
true

> can(tonumber("hello"))
false

> type("hello")
string

> type(42)
number

> type([1, 2, 3])
tuple
```

### Practical Use

```hcl
# Safe variable parsing with try()
variable "config_json" {
  default = "{\"replicas\": 3}"
}

locals {
  config   = try(jsondecode(var.config_json), {})
  replicas = try(local.config.replicas, 1)
}

# Validation with can()
variable "port" {
  type = string
  validation {
    condition     = can(tonumber(var.port))
    error_message = "Port must be a valid number."
  }
}
```

---

## 10. Hands-On Exercises

### Exercise 1: Function Chaining in Console

```bash
terraform console
```

Try these compound expressions:

```
> upper(join("-", ["hello", "terraform", "world"]))
"HELLO-TERRAFORM-WORLD"

> length(distinct(flatten([["a","b"],["b","c"],["c","d"]])))
4

> { for k, v in zipmap(["a","b","c"], [1,2,3]) : upper(k) => v * 10 }
{"A" = 10, "B" = 20, "C" = 30}

> [for s in ["hello.tf", "world.py", "main.tf"] : s if endswith(s, ".tf")]
["hello.tf", "main.tf"]

> merge(
    { for env in ["dev", "staging", "prod"] :
      env => cidrsubnet("10.0.0.0/8", 8, index(["dev","staging","prod"], env))
    }
  )
{"dev" = "10.0.0.0/16", "prod" = "10.2.0.0/16", "staging" = "10.1.0.0/16"}
```

### Exercise 2: Build a Name Generator

```hcl
# main.tf
variable "project" { default = "acme" }
variable "environment" { default = "prod" }
variable "component" { default = "web-server" }

locals {
  # Standard name: acme-prod-web-server
  standard_name = join("-", [var.project, var.environment, var.component])

  # Short name for resources with length limits: acme-prod-web-a1b2
  short_name = format("%s-%s-%s-%s",
    var.project,
    var.environment,
    substr(var.component, 0, 3),
    substr(md5(local.standard_name), 0, 4)
  )

  # S3 bucket name (must be globally unique, lowercase, no underscores)
  bucket_name = lower(replace(
    format("%s-%s-%s-%s", var.project, var.environment, var.component,
           substr(md5("${var.project}${var.environment}"), 0, 8)),
    "_", "-"
  ))
}

output "standard_name" { value = local.standard_name }
output "short_name"    { value = local.short_name }
output "bucket_name"   { value = local.bucket_name }
```

```bash
$ terraform apply -auto-approve

standard_name = "acme-prod-web-server"
short_name    = "acme-prod-web-a1b2"
bucket_name   = "acme-prod-web-server-1a2b3c4d"
```

---

## Quick Reference Cheat Sheet

```
STRING          lower upper trim split join format replace substr
NUMERIC         abs ceil floor max min pow
COLLECTION      length concat flatten keys values lookup merge
                contains distinct sort zipmap range
ENCODING        base64encode jsonencode yamlencode urlencode csvdecode
FILESYSTEM      file templatefile abspath basename dirname fileexists
DATE/TIME       timestamp formatdate timeadd timecmp
HASH            md5 sha256 sha512 bcrypt uuid base64sha256
IP NETWORK      cidrsubnet cidrhost cidrnetmask cidrsubnets
TYPE            tostring tonumber tolist tomap toset try can type
```

> **Key takeaway:** Terraform functions eliminate hard-coding and make configurations dynamic. Master `cidrsubnet`, `lookup`, `merge`, `templatefile`, and `format` --- these five handle 80% of real-world needs.
