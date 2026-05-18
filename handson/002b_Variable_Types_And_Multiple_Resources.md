# 002b — Variable Types & Multiple Resources with for_each

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~10 minutes

---

## Concept

Terraform variables aren't just strings. You can use numbers, booleans, lists, and maps. Combined with `for_each`, a single resource block creates multiple resources from a map.

```
variable types:

  string  →  "hello"
  number  →  42
  bool    →  true / false
  list    →  ["a", "b", "c"]
  map     →  { key = "value" }

for_each with a map:

  map = { greeting="/tmp/g.txt", farewell="/tmp/f.txt" }
         │                       │
         ▼                       ▼
  local_file["greeting"]   local_file["farewell"]
```

---

## Prerequisites

Continue in the same directory from 002a:

```bash
cd ~/tf_works/002_variables
```

---

## Step 1 — Add more variable types

Update `variables.tf`:

```bash
cat > variables.tf << 'EOF'
variable "message" {
  description = "The greeting message"
  type        = string
  default     = "Hello Folks of MassMutual"
}

variable "file_count" {
  description = "Number of files to create"
  type        = number
  default     = 3
}

variable "add_timestamp" {
  description = "Whether to add a timestamp line"
  type        = bool
  default     = true
}

variable "team_members" {
  description = "List of team member names"
  type        = list(string)
  default     = ["Alice", "Bob", "Charlie"]
}

variable "file_config" {
  description = "Configuration per file"
  type = map(string)
  default = {
    greeting  = "/tmp/greeting.txt"
    farewell  = "/tmp/farewell.txt"
    reminder  = "/tmp/reminder.txt"
  }
}
EOF
```

### Variable Types Cheat Sheet

```
string    →  "hello"               var.message
number    →  42                    var.file_count
bool      →  true / false         var.add_timestamp
list      →  ["a", "b", "c"]     var.team_members[0]
map       →  { key = "value" }    var.file_config["greeting"]
```

---

## Step 2 — Create multiple files using for_each

Update `main.tf`:

```bash
cat > main.tf << 'EOF'
resource "local_file" "configs" {
  for_each = var.file_config

  filename = each.value
  content  = <<-EOT
    File: ${each.key}
    Message: ${var.message}
    Team: ${join(", ", var.team_members)}
    Timestamp enabled: ${var.add_timestamp}
  EOT
}
EOF
```

### How for_each works

```
for_each = var.file_config
           │
           └── Iterates over the map:
               "greeting" = "/tmp/greeting.txt"
               "farewell" = "/tmp/farewell.txt"
               "reminder" = "/tmp/reminder.txt"

each.key   → "greeting", "farewell", "reminder"
each.value → "/tmp/greeting.txt", "/tmp/farewell.txt", "/tmp/reminder.txt"
```

---

## Step 3 — Apply

```bash
terraform apply -auto-approve
```

```
local_file.configs["farewell"]: Creating...
local_file.configs["greeting"]: Creating...
local_file.configs["reminder"]: Creating...
local_file.configs["farewell"]: Creation complete after 0s
local_file.configs["greeting"]: Creation complete after 0s
local_file.configs["reminder"]: Creation complete after 0s

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

---

## Step 4 — Verify all files

```bash
for f in greeting farewell reminder; do
  echo "=== $f ==="
  cat "/tmp/$f.txt"
  echo
done
```

```
=== greeting ===
  File: greeting
  Message: Hello Folks of MassMutual
  Team: Alice, Bob, Charlie
  Timestamp enabled: true

=== farewell ===
  File: farewell
  Message: Hello Folks of MassMutual
  Team: Alice, Bob, Charlie
  Timestamp enabled: true

=== reminder ===
  File: reminder
  Message: Hello Folks of MassMutual
  Team: Alice, Bob, Charlie
  Timestamp enabled: true
```

---

## Step 5 — Check state

```bash
terraform state list
```

```
local_file.configs["farewell"]
local_file.configs["greeting"]
local_file.configs["reminder"]
```

> Each resource is keyed by name, not index. If you remove "farewell" from the map, ONLY that file is destroyed. Others untouched. This is why `for_each` is preferred over `count`.

---

## Step 6 — String interpolation and functions used

```
${each.key}                      ← Current map key
${each.value}                    ← Current map value
${var.message}                   ← String variable
${join(", ", var.team_members)}  ← join() turns list → comma-separated string
${var.add_timestamp}             ← Bool rendered as "true"/"false"
```

> **Tip:** Use `terraform console` to test expressions interactively:

```bash
terraform console
```

```
> var.team_members
tolist(["Alice", "Bob", "Charlie"])

> join(", ", var.team_members)
"Alice, Bob, Charlie"

> var.team_members[0]
"Alice"

> length(var.file_config)
3

> exit
```

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| `number` type | Integer/float variables |
| `bool` type | true/false flags |
| `list(string)` | Ordered collection |
| `map(string)` | Key-value pairs |
| `for_each` | Create resources from a map |
| `each.key` / `each.value` | Access current iteration |
| `join()` | Convert list to string |
| `terraform console` | Interactive expression testing |
| Key-based state | Removing a map key only destroys that resource |

> **Next:** Proceed to **002c** for outputs, sensitive files, and validation.
