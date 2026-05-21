# Lab 060 — Terraform Sentinel Policy as Code

**By: Saravanan Sundaramoorthy**
**Environment:** Terraform Cloud (HCP Terraform) + GitHub + optional Sentinel CLI
**Time:** ~50 minutes

---

## What You'll Learn

| Topic | Concept |
|-------|---------|
| Sentinel overview | Policy as Code framework built into Terraform Cloud/Enterprise |
| Workflow position | Runs after `plan`, before `apply` — a mandatory gate |
| Enforcement levels | `advisory`, `soft-mandatory`, `hard-mandatory` — three ways to enforce |
| Policy file structure | `.sentinel` policy file + `sentinel.hcl` configuration |
| Policy sets | How policies are grouped and attached to workspaces |
| `tfplan/v2` import | The standard import for reading Terraform plan data in Sentinel |
| Tag policy | Require `owner` and `project` tags on every `aws_instance` |
| Instance-type policy | Restrict instance types to an approved list |
| Passing and failing runs | What the UI shows for pass, advisory fail, and soft-mandatory fail |
| Sentinel CLI | Local policy testing without Terraform Cloud |

---

## Concept: What Is Sentinel?

Sentinel is HashiCorp's **Policy as Code** framework. It is built into Terraform Cloud and Terraform Enterprise. Sentinel policies are small programs (written in the Sentinel language) that evaluate the Terraform plan and decide whether the run can proceed.

```
Developer laptop / GitHub
        │
        │  git push
        ▼
Terraform Cloud
  ┌─────────────────────────────────────────────────────┐
  │  1. terraform plan  ← plan is generated              │
  │                                                       │
  │  2. Sentinel runs   ← policies evaluate the plan     │
  │     ├── require-resource-tags  (advisory)             │
  │     └── restrict-instance-types  (soft-mandatory)    │
  │                                                       │
  │  3. terraform apply ← only reached if policies pass  │
  │     (or overridden for soft-mandatory)                │
  └─────────────────────────────────────────────────────┘
```

Key point: Sentinel sits **between plan and apply**. No matter how the run was triggered (VCS push, CLI, UI), the policies run automatically on every plan.

---

## Concept: Where Sentinel Fits in the Workflow

```
terraform plan  →  [Sentinel policies run]  →  terraform apply
```

The Sentinel evaluation step appears in the Terraform Cloud run page as the **Policy Check** phase:

```
Run lifecycle:
  Plan       → PASSED
  Policy Check → PASSED  ←── Sentinel runs here
  Apply      → PASSED
```

If a policy fails and the enforcement level allows it (soft-mandatory), a human with override permission can click **Override** in the UI and let the apply proceed anyway. With hard-mandatory, there is no override — the run is blocked.

---

## Concept: Enforcement Levels

| Level | Behaviour on fail | Can be overridden? | Typical use |
|-------|------------------|--------------------|-------------|
| `advisory` | Warning is logged; **apply still proceeds** | N/A — apply runs regardless | Informational checks, gradual rollout of new policy |
| `soft-mandatory` | Run is blocked; **an authorized human can override** | Yes — team member with Override Policies permission | Cost guardrails, unapproved instance types |
| `hard-mandatory` | Run is blocked; **no override possible** | No | Security mandates, regulatory compliance |

---

## Concept: Policy File Structure

A Sentinel policy consists of two files:

```
policy-set/
├── require-resource-tags.sentinel    # policy logic
├── restrict-instance-types.sentinel  # policy logic
└── sentinel.hcl                      # wires policies together with enforcement levels
```

**`require-resource-tags.sentinel`** — the policy logic, written in the Sentinel language.

**`sentinel.hcl`** — the policy set configuration that declares which `.sentinel` files exist and what enforcement level each one has.

---

## Concept: Policy Sets

A **policy set** is a collection of Sentinel policies that are attached to one or more workspaces in an organization. You can:

- Attach a policy set to **all workspaces** in the organization (global enforcement)
- Attach to **specific workspaces** (per-project enforcement)
- Attach multiple policy sets to the same workspace

Terraform Cloud pulls the policy set from a GitHub repository you specify. Every commit to that repo triggers a policy set version update.

```
Organization
└── Policy Set: "compliance-policies"   ← backed by GitHub repo
    ├── require-resource-tags.sentinel
    ├── restrict-instance-types.sentinel
    ├── sentinel.hcl
    └── Attached to workspaces:
        ├── prod-us-east-1
        ├── prod-eu-west-1
        └── staging-us-east-1
```

---

## Part A — Create the Policy GitHub Repository

### Step A1 — Create the repo

1. Go to [https://github.com/new](https://github.com/new)
2. Repository name: `tf-sentinel-060-policies`
3. Visibility: **Public**
4. Check **Add a README file**
5. Click **Create repository**

All policy files in the following steps are created inside this repository.

---

## Part B — Policy 1: Require Resource Tags (Advisory)

This policy checks that every `aws_instance` resource in the plan has both an `owner` tag and a `project` tag set to a non-empty value. The enforcement level is `advisory` — a missing tag generates a warning but does not block the apply.

### Step B1 — Create `require-resource-tags.sentinel`

In GitHub, click **Add file → Create new file**, name it `require-resource-tags.sentinel`, paste:

```python
# require-resource-tags.sentinel
# Advisory policy: every aws_instance must have 'owner' and 'project' tags.

# Import the Terraform plan data using the v2 API.
import "tfplan/v2" as tfplan

# required_tags lists the tag keys that must be present on every aws_instance.
required_tags = ["owner", "project"]

# all_aws_instances collects all aws_instance resources that are being
# created or updated in this plan.
# tfplan.resource_changes is a map keyed by the resource address.
# We filter to resources where:
#   - type is "aws_instance"
#   - change.actions contains "create" or "update"
all_aws_instances = filter tfplan.resource_changes as _, rc {
    rc.type is "aws_instance" and
    (rc.change.actions contains "create" or rc.change.actions contains "update")
}

# tag_check returns true if a single resource change has all required tags
# with non-empty values.
tag_check = rule {
    all all_aws_instances as _, rc {
        all required_tags as tag {
            rc.change.after.tags[tag] is not null and
            rc.change.after.tags[tag] is not ""
        }
    }
}

# main is the entry point. Sentinel evaluates this rule to determine pass/fail.
main = rule {
    tag_check
}
```

**Explanation of each section:**

| Section | Purpose |
|---------|---------|
| `import "tfplan/v2" as tfplan` | Loads the Terraform plan data. `tfplan/v2` is the standard Sentinel import for Terraform Cloud runs. |
| `all_aws_instances = filter ...` | Builds a collection of every `aws_instance` resource that will be created or updated. Skipped resources (`no-op`, `delete`) are excluded. |
| `rc.change.after` | The attributes the resource will have **after** the apply — i.e., the proposed new state. |
| `rc.change.after.tags[tag]` | Reads the value of a specific tag key from the proposed resource attributes. |
| `tag_check = rule { all ... }` | A named rule. `all` iterates over every resource and every required tag, returning `true` only if none of them is null or empty. |
| `main = rule { tag_check }` | The required entry point. Sentinel evaluates `main` to decide pass or fail. |

Commit the file directly to `main`.

---

## Part C — Policy 2: Restrict Instance Types (Soft-Mandatory)

This policy ensures that only pre-approved, cost-controlled instance types are used for any `aws_instance`. If a plan contains `t3.medium` or any other unapproved type, the policy fails. The enforcement level is `soft-mandatory` — the run is blocked, but a team lead with override permission can unblock it.

### Step C1 — Create `restrict-instance-types.sentinel`

In GitHub, create `restrict-instance-types.sentinel`:

```python
# restrict-instance-types.sentinel
# Soft-mandatory policy: aws_instance must use an approved instance type.

import "tfplan/v2" as tfplan
import "strings"

# allowed_types is the whitelist of approved instance types.
# Only these types are permitted in any workspace this policy set is attached to.
allowed_types = [
    "t2.micro",
    "t3.micro",
    "t3.small",
]

# all_aws_instances collects resources being created or updated.
all_aws_instances = filter tfplan.resource_changes as _, rc {
    rc.type is "aws_instance" and
    (rc.change.actions contains "create" or rc.change.actions contains "update")
}

# instance_type_allowed checks that a single resource's proposed instance_type
# is present in the allowed_types list.
# strings.has_suffix is not used here — we do a direct list membership check.
instance_type_allowed = func(rc) {
    return rc.change.after.instance_type in allowed_types
}

# type_check iterates over every aws_instance and verifies its instance type.
type_check = rule {
    all all_aws_instances as _, rc {
        instance_type_allowed(rc)
    }
}

# main is the entry point.
main = rule {
    type_check
}
```

**Explanation of each section:**

| Section | Purpose |
|---------|---------|
| `import "strings"` | Loads the Sentinel standard strings library. Imported here for completeness; `in` operator is used for the list check. |
| `allowed_types = [...]` | The approved list. Change this list to expand or tighten the policy. |
| `instance_type_allowed = func(rc)` | A reusable function that returns `true` if the instance type is in the allowed list. |
| `rc.change.after.instance_type` | The proposed instance type attribute from the plan. |
| `value in list` | Sentinel's `in` operator returns `true` if the value is an element of the list. |
| `type_check = rule { all ... }` | Named rule that evaluates every instance. |
| `main = rule { type_check }` | Entry point Sentinel evaluates. |

Commit the file.

---

## Part D — Create `sentinel.hcl`

The `sentinel.hcl` file is the policy set configuration. It lists every policy file and assigns enforcement levels.

### Step D1 — Create `sentinel.hcl`

In GitHub, create `sentinel.hcl`:

```hcl
# sentinel.hcl
# Policy set configuration for the compliance-policies set.
# This file wires .sentinel policy files to enforcement levels.

policy "require-resource-tags" {
  source            = "./require-resource-tags.sentinel"
  enforcement_level = "advisory"
}

policy "restrict-instance-types" {
  source            = "./restrict-instance-types.sentinel"
  enforcement_level = "soft-mandatory"
}
```

**File structure after all commits:**

```
tf-sentinel-060-policies/
├── README.md
├── require-resource-tags.sentinel
├── restrict-instance-types.sentinel
└── sentinel.hcl
```

---

## Part E — Connect the Policy Set to Terraform Cloud

### Step E1 — Navigate to Policy Sets

1. Log in to [https://app.terraform.io](https://app.terraform.io)
2. Go to your organization (e.g. `robochef-training`)
3. Click **Settings** (gear icon, top-right of the org dashboard)
4. In the left sidebar, click **Policy Sets**
5. Click **Connect a new policy set**

### Step E2 — Connect to GitHub

1. Under **Connect to a version control provider**, choose **GitHub.com**
   (This is the same OAuth connection used in Lab 059. If not set up, complete Part C of Lab 059 first.)
2. Find and click **tf-sentinel-060-policies**

### Step E3 — Configure the policy set

| Setting | Value |
|---------|-------|
| Policy Set Name | `compliance-policies` |
| Description | `Require tags and restrict instance types` |
| Policies Path | *(leave blank — `sentinel.hcl` is at the root)* |
| VCS Branch | `main` |
| **Scope of Policies** | Choose one of the two options below |

**Scope options:**

| Scope | Effect |
|-------|--------|
| **Policies enforced on all workspaces** | Every workspace in the org gets these policies automatically — good for global compliance |
| **Policies enforced on selected workspaces** | Choose specific workspaces — good for testing a new policy set before rolling it out broadly |

For this lab, choose **Policies enforced on all workspaces** to see it in action on the next run.

6. Click **Connect policy set**

The policy set now appears in the list:

```
compliance-policies
  Source: github.com/saravanans/tf-sentinel-060-policies (main)
  Scope:  All workspaces
  Policies: require-resource-tags (advisory)
            restrict-instance-types (soft-mandatory)
```

---

## Part F — Simulate a Passing Run

Trigger a new plan on any workspace that has `aws_instance` resources with proper `owner` and `project` tags and an approved instance type (e.g. `t3.micro`).

**Example `main.tf` that will pass both policies:**

```hcl
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"

  tags = {
    owner   = "saravanans"
    project = "robochef.co"
    env     = "staging"
  }
}
```

**What the Terraform Cloud run page shows (Policy Check phase):**

```
Policy Check

  require-resource-tags  (advisory)       — PASS
  restrict-instance-types (soft-mandatory) — PASS

Policy check passed.
```

The run proceeds to the Apply phase automatically (or with the usual manual confirm, depending on workspace auto-apply settings).

---

## Part G — Simulate a Failing Run: Advisory (Tag Missing)

Change `main.tf` to remove the `owner` tag:

```hcl
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"

  tags = {
    # owner tag is intentionally missing
    project = "robochef.co"
  }
}
```

Push the change. In the Terraform Cloud UI, the Policy Check phase shows:

```
Policy Check

  require-resource-tags  (advisory)       — FAIL  ⚠ (warning)
  restrict-instance-types (soft-mandatory) — PASS

Advisory policies failed. The run is allowed to continue.
```

Because `require-resource-tags` is `advisory`, Terraform Cloud logs the warning and **continues to the Apply phase**. The apply proceeds without any human action.

**Key behaviour:** Advisory failures never block a run. They create a visible audit trail so teams can track non-compliant resources while a harder enforcement policy is being phased in.

---

## Part H — Simulate a Failing Run: Soft-Mandatory (Wrong Instance Type)

Change `main.tf` to use a non-approved instance type:

```hcl
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.medium"   # not in the allowed_types list

  tags = {
    owner   = "saravanans"
    project = "robochef.co"
  }
}
```

Push the change. The Policy Check phase shows:

```
Policy Check

  require-resource-tags  (advisory)       — PASS
  restrict-instance-types (soft-mandatory) — FAIL  ✗ (blocked)

Soft-mandatory policies failed. A user with override permissions can allow
this run to continue.

  [Override & Continue]   [Discard Run]
```

**Two outcomes from here:**

| Action | Result |
|--------|--------|
| **Override & Continue** | A user with "Override Policy Checks" permission clicks the button. The run proceeds to Apply. The override is logged in the audit trail with the user's name and timestamp. |
| **Discard Run** | The run is discarded. The apply never happens. Developer must change the config to use an approved instance type. |

**Audit trail entry (visible in the run timeline):**

```
Policy override by: saravanans
Reason: Approved exception for performance testing — expires 2026-06-01
Policies overridden: restrict-instance-types
```

---

## Part I — Sentinel CLI (Local Testing Without Terraform Cloud)

You can test Sentinel policies locally on your machine before committing them to GitHub, using the Sentinel CLI.

### Step I1 — Install the Sentinel CLI

```bash
# Download the latest Sentinel CLI from releases.hashicorp.com
# Replace 0.26.3 with the current version shown at:
# https://releases.hashicorp.com/sentinel/

SENTINEL_VERSION="0.26.3"
wget "https://releases.hashicorp.com/sentinel/${SENTINEL_VERSION}/sentinel_${SENTINEL_VERSION}_linux_amd64.zip"
unzip "sentinel_${SENTINEL_VERSION}_linux_amd64.zip"
sudo mv sentinel /usr/local/bin/
rm "sentinel_${SENTINEL_VERSION}_linux_amd64.zip"

sentinel version
# Sentinel v0.26.3
```

### Step I2 — Quick policy evaluation with `sentinel apply`

```bash
sentinel apply require-resource-tags.sentinel
```

Expected (without mock data):

```
Pass
```

> Without mock data the `filter` expression returns an empty collection. An empty collection means the `all` rule evaluates to `true` (vacuous truth). The policy passes trivially. This is why mock data is essential for meaningful local tests.

### Step I3 — Create mock data

Mock data simulates the `tfplan/v2` import so the policy runs against a realistic plan. Create the directory structure:

```
test/
└── require-resource-tags/
    ├── pass.json         # a plan with correct tags
    ├── fail.json         # a plan with missing owner tag
    └── sentinel.json     # tells sentinel which mock to use for which import
```

**`test/require-resource-tags/sentinel.json`** — maps Sentinel imports to mock files:

```json
{
  "mock": {
    "tfplan/v2": "mock-tfplan-v2.sentinel.json"
  }
}
```

**`test/require-resource-tags/mock-tfplan-v2.sentinel.json`** — minimal mock that mimics the `tfplan/v2` data structure:

```json
{
  "resource_changes": {
    "aws_instance.web": {
      "address": "aws_instance.web",
      "type": "aws_instance",
      "change": {
        "actions": ["create"],
        "before": null,
        "after": {
          "instance_type": "t3.micro",
          "tags": {
            "owner":   "saravanans",
            "project": "robochef.co"
          }
        }
      }
    }
  }
}
```

**`test/require-resource-tags/pass.json`** — a test case that should pass:

```json
{
  "mock": {
    "tfplan/v2": {
      "resource_changes": {
        "aws_instance.web": {
          "address": "aws_instance.web",
          "type": "aws_instance",
          "change": {
            "actions": ["create"],
            "before": null,
            "after": {
              "instance_type": "t3.micro",
              "tags": {
                "owner":   "saravanans",
                "project": "robochef.co"
              }
            }
          }
        }
      }
    }
  }
}
```

**`test/require-resource-tags/fail.json`** — a test case that should fail (missing `owner`):

```json
{
  "mock": {
    "tfplan/v2": {
      "resource_changes": {
        "aws_instance.web": {
          "address": "aws_instance.web",
          "type": "aws_instance",
          "change": {
            "actions": ["create"],
            "before": null,
            "after": {
              "instance_type": "t3.micro",
              "tags": {
                "project": "robochef.co"
              }
            }
          }
        }
      }
    }
  }
}
```

### Step I4 — Run the test suite with `sentinel test`

```bash
sentinel test require-resource-tags.sentinel
```

Expected output:

```
PASS - require-resource-tags.sentinel
  PASS - test/require-resource-tags/pass.json
  FAIL - test/require-resource-tags/fail.json
```

> The `FAIL` for `fail.json` is **correct behaviour** — it means the policy correctly caught the missing `owner` tag in that test case. In Sentinel testing, a test case marked `fail` in the expected field means the policy should produce a fail result; if it does, the test passes.

To mark `fail.json` as an *expected* fail (so `sentinel test` reports it as a passing test scenario), add an `"expected_result"` field to `fail.json`:

```json
{
  "expected_result": "fail",
  "mock": {
    ...
  }
}
```

Then:

```bash
sentinel test require-resource-tags.sentinel
```

```
PASS - require-resource-tags.sentinel
  PASS - test/require-resource-tags/pass.json
  PASS - test/require-resource-tags/fail.json
```

Both test cases pass: the pass scenario produces `true`, the fail scenario produces `false` — both match expectations.

---

## Part J — Cleanup

No Terraform infrastructure is created in this lab (Sentinel runs before apply and we only used advisory/soft-mandatory which can be discarded). Clean up the policy set when done:

1. Terraform Cloud → **Organization Settings → Policy Sets**
2. Click **compliance-policies**
3. Click **Delete policy set**
4. Confirm deletion

To remove the GitHub repositories:

1. `tf-sentinel-060-policies` → **Settings → Danger Zone → Delete this repository**

No local `.terraform` directories were created in this lab — no cleanup needed on disk.

---

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| **Sentinel** | HashiCorp's Policy as Code framework. Policies are programs that evaluate the Terraform plan and return pass or fail. |
| **Policy as Code** | Expressing compliance rules as version-controlled code rather than manual processes or documentation. |
| **`tfplan/v2`** | The standard Sentinel import that provides access to `resource_changes`, `variables`, `outputs`, and other plan data from a Terraform Cloud run. |
| **`resource_changes`** | A map in `tfplan/v2` keyed by resource address. Each entry has `type`, `change.actions`, `change.before`, and `change.after`. |
| **`advisory`** | Enforcement level: policy failure is logged as a warning but the apply is not blocked. |
| **`soft-mandatory`** | Enforcement level: policy failure blocks the apply; an authorized user can override and allow the run to proceed. |
| **`hard-mandatory`** | Enforcement level: policy failure blocks the apply with no override possible. |
| **Policy Set** | A collection of `.sentinel` policy files + a `sentinel.hcl` config file, backed by a VCS repo, attached to workspaces in an org. |
| **`sentinel.hcl`** | The policy set configuration file. Declares which `.sentinel` files are in the set and their enforcement levels. |
| **Mock data** | Synthetic `tfplan/v2` data used with `sentinel test` to validate policy logic locally without a real Terraform Cloud run. |
| **Sentinel CLI** | The `sentinel` binary. Used locally for `sentinel apply` (quick eval) and `sentinel test` (test suite with mock data). |

---

## Common Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `import "tfplan/v2": could not import` | Running `sentinel apply` locally without mock data for the import | Create a `mock-tfplan-v2.sentinel.json` file and reference it in `sentinel.json` |
| Policy always passes even with bad data | Mock data structure is wrong — `resource_changes` is missing or keys are mistyped | Print `tfplan.resource_changes` in the policy to inspect what Sentinel actually sees: add `print(tfplan.resource_changes)` temporarily |
| `filter` returns empty collection | The `type` check or `actions` check in the filter does not match the mock data | Verify `rc.type` matches `"aws_instance"` exactly, and `rc.change.actions` is a list like `["create"]` |
| `rc.change.after.tags is undefined` | The mock's `after` block has no `tags` key at all | Add `"tags": {}` to the `after` block in the mock — even an empty map is needed |
| `null reference` in tag check | A tag key exists in the required list but is completely absent from `after.tags` | Use `rc.change.after.tags[tag] else null is not null` to safely handle absent keys |
| Policies not running on a workspace | Policy set is not attached to that workspace | Settings → Policy Sets → edit the policy set → add the workspace under Scope |
| Policy set version not updating | GitHub commit was to the wrong branch | Check the VCS branch configured in the policy set settings matches the branch you pushed to |

---

## Concept Summary

```
Sentinel: Policy as Code for Terraform Cloud / Enterprise
  ─────────────────────────────────────────────────────────
  Position in workflow:
    terraform plan  →  [Sentinel policy check]  →  terraform apply

  Enforcement levels:
    advisory        → warn only, apply proceeds automatically
    soft-mandatory  → blocks apply; authorized user can override in UI
    hard-mandatory  → blocks apply; no override, ever

  Policy file structure:
    require-resource-tags.sentinel    ← Sentinel language logic
    restrict-instance-types.sentinel  ← Sentinel language logic
    sentinel.hcl                      ← wires files to enforcement levels

  tfplan/v2 resource access pattern:
    import "tfplan/v2" as tfplan
    instances = filter tfplan.resource_changes as _, rc {
        rc.type is "aws_instance" and
        rc.change.actions contains "create"
    }
    main = rule {
        all instances as _, rc { rc.change.after.<attribute> == <expected> }
    }

  Policy sets:
    Backed by a GitHub repo  →  attached to org or specific workspaces
    Every commit to the repo updates the policy set version automatically

  Local testing with Sentinel CLI:
    sentinel apply <policy.sentinel>   ← quick evaluation
    sentinel test  <policy.sentinel>   ← full test suite with mock data
    Mock data mimics tfplan/v2 so policies run without a real plan

  Tag policy (advisory):
    Checks rc.change.after.tags["owner"] and rc.change.after.tags["project"]
    Missing or empty tag → advisory warning, apply still runs

  Instance type policy (soft-mandatory):
    Checks rc.change.after.instance_type in ["t2.micro","t3.micro","t3.small"]
    Unapproved type → apply blocked, override available in UI

  Owner: saravanans
  Project: robochef.co
```
