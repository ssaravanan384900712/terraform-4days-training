# 015 — Keepers: Controlled Recreation

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~10 minutes

---

## Concept

Random resources persist in state — apply twice, same value. But sometimes you WANT a new value (new deployment, new version). **Keepers** give you that control: change a keeper → resource is destroyed and recreated with a new value.

```
keepers = { version = "1.0.0" }  →  random_pet = "sunny-cobra"
keepers = { version = "1.0.0" }  →  random_pet = "sunny-cobra"  (same!)
keepers = { version = "2.0.0" }  →  random_pet = "noble-whale"  (NEW! keeper changed)
```

> This is the same pattern as AWS: change AMI ID → EC2 instance replaced. Keepers teach this safely without cloud costs.

---

## Prerequisites

Continue from 009 (or create a fresh project):

```bash
cd ~/tf_works/003_random
```

---

## Step 1 — Create a random_pet with keepers

```bash
cat > keepers.tf << 'EOF'
variable "app_version" {
  description = "Changing this regenerates the app name"
  type        = string
  default     = "1.0.0"
}

resource "random_pet" "app" {
  keepers = {
    version = var.app_version
  }
  length = 2
}

output "app_name" {
  value = "app-${random_pet.app.id}-v${var.app_version}"
}
EOF
```

### What does keepers do?

```
keepers = {
  version = var.app_version    ← Terraform watches this value
}

If version stays "1.0.0" → same pet name every apply
If version changes to "2.0.0" → pet is DESTROYED and RECREATED
```

---

## Step 2 — Apply

```bash
terraform apply -auto-approve
```

```
random_pet.app: Creating...
random_pet.app: Creation complete after 0s [id=sunny-cobra]

app_name = "app-sunny-cobra-v1.0.0"
```

---

## Step 3 — Apply again — same keeper, no change

```bash
terraform apply -auto-approve
```

```
No changes. Your infrastructure matches the configuration.
```

> Same keeper value `"1.0.0"` → same pet name `"sunny-cobra"`. Idempotent.

---

## Step 4 — Change the version → forces replacement

```bash
terraform apply -auto-approve -var='app_version=2.0.0'
```

```
  # random_pet.app must be replaced
-/+ resource "random_pet" "app" {
      ~ id       = "sunny-cobra" -> (known after apply)
      ~ keepers  = {
          ~ "version" = "1.0.0" -> "2.0.0"    # forces replacement
        }
    }

random_pet.app: Destroying... [id=sunny-cobra]
random_pet.app: Destruction complete after 0s
random_pet.app: Creating...
random_pet.app: Creation complete after 0s [id=noble-whale]

app_name = "app-noble-whale-v2.0.0"
```

> **`# forces replacement`** — the keeper value changed, so Terraform destroyed the old resource and created a new one with a new random value.

---

## Step 5 — Multiple keepers

```bash
cat > keepers.tf << 'EOF'
variable "app_version" {
  type    = string
  default = "2.0.0"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

resource "random_pet" "app" {
  keepers = {
    version = var.app_version
    region  = var.region
  }
  length = 2
}

output "app_name" {
  value = "app-${random_pet.app.id}-v${var.app_version}-${var.region}"
}
EOF
```

```bash
terraform apply -auto-approve
```

```
app_name = "app-noble-whale-v2.0.0-us-east-1"
```

Now change ONLY the region:

```bash
terraform apply -auto-approve -var='region=eu-west-1'
```

```
  # random_pet.app must be replaced
-/+ resource "random_pet" "app" {
      ~ keepers = {
          ~ "region"  = "us-east-1" -> "eu-west-1"    # forces replacement
            "version" = "2.0.0"
        }
    }

app_name = "app-fast-puma-v2.0.0-eu-west-1"
```

> Changing ANY keeper triggers replacement. All keepers must stay the same for the value to persist.

---

## Step 6 — Keepers with random_id (practical use case)

This is how you'll use keepers with AWS later — unique S3 bucket names per deployment:

```bash
cat > deploy_id.tf << 'EOF'
variable "deploy_tag" {
  type    = string
  default = "initial"
}

resource "random_id" "bucket_suffix" {
  keepers = {
    deploy = var.deploy_tag
  }
  byte_length = 4
}

output "bucket_name" {
  value = "myapp-data-${random_id.bucket_suffix.hex}"
}
EOF
```

```bash
terraform apply -auto-approve
```

```
bucket_name = "myapp-data-a1b2c3d4"
```

```bash
terraform apply -auto-approve -var='deploy_tag=release-2'
```

```
bucket_name = "myapp-data-e5f6a7b8"
```

> New deployment tag → new unique bucket suffix. Same tag → same suffix (idempotent).

---

## AWS Equivalent (Preview)

```
What keepers teach:                    AWS equivalent:
──────────────────────                 ──────────────
keeper changed → recreate              AMI ID changed → new EC2 instance
keeper same → no change                AMI ID same → instance untouched
multiple keepers → any change triggers instance_type change → in-place update
                                       AMI change → forces replacement
```

---

## Clean Up

```bash
rm keepers.tf deploy_id.tf
terraform apply -auto-approve   # removes keeper resources
```

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| `keepers` | Map of values that trigger recreation when changed |
| Same keeper → same value | Idempotent — no change |
| Changed keeper → replacement | `-/+` destroy and recreate |
| `# forces replacement` | Plan shows which attribute caused it |
| Multiple keepers | ANY keeper change triggers recreation |
| AWS analogy | Keepers = AMI changes forcing EC2 replacement |

> **Next:** Proceed to **011** for count and for_each — creating multiple resources.
