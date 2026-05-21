# 029 — Terraform AWS Lambda & API Gateway

**By: Saravanan Sundaramoorthy**
**Environment:** AWS ap-south-1 (Mumbai)
**Time to complete:** ~15 minutes

---

## Topic

| Concept | What it means |
|---------|--------------|
| **`archive_file`** | Terraform data source that zips a source file or directory into a `.zip` for Lambda |
| **`source_code_hash`** | SHA-256 of the zip; forces Lambda to re-deploy whenever the code changes |
| **IAM execution role** | The role Lambda assumes at runtime; must trust `lambda.amazonaws.com` |
| **`AWSLambdaBasicExecutionRole`** | AWS-managed policy granting Lambda permission to write CloudWatch logs |
| **API Gateway v2 (HTTP API)** | Simpler, cheaper gateway type; supports Lambda proxy integration out of the box |
| **`AWS_PROXY` integration** | API Gateway forwards the full HTTP request to Lambda and returns Lambda's response verbatim |
| **`payload_format_version = "2.0"`** | Determines the event object shape Lambda receives; 2.0 uses `rawPath`, `rawQueryString`, etc. |
| **`aws_lambda_permission`** | Grants API Gateway the right to invoke the Lambda function; scoped to a specific API ARN |
| **`$default` stage + `auto_deploy`** | Creates a live stage instantly without manual deployments; URL is active immediately after apply |

---

## Architecture

```
Internet
   |
   v
aws_apigatewayv2_api  (HTTP API)
   |
   | GET /
   v
aws_apigatewayv2_route  (GET $default)
   |
   v
aws_apigatewayv2_integration  (AWS_PROXY, payload 2.0)
   |
   v
aws_lambda_function  (terraform-029-api-handler, python3.12)
   |
   v
src/handler.py  →  {"message": "Hello from robochef.co Lambda!"}

IAM:
  aws_iam_role (lambda-exec-role)
    └── aws_iam_role_policy_attachment (AWSLambdaBasicExecutionRole)

Permissions:
  aws_lambda_permission (AllowAPIGatewayInvoke)
    └── source_arn = api_arn/*/*

Packaging:
  archive_file (data source) → handler.zip
```

---

## What Terraform Creates

| Resource | Description |
|---------|-------------|
| `aws_iam_role.lambda_exec` | Execution role Lambda assumes; trust policy allows `lambda.amazonaws.com` |
| `aws_iam_role_policy_attachment.basic` | Attaches AWS-managed `AWSLambdaBasicExecutionRole` policy to the role |
| `aws_lambda_function.api_handler` | Python 3.12 function with source_code_hash for change detection |
| `aws_apigatewayv2_api.http_api` | HTTP API (v2) — cheaper and simpler than REST API (v1) |
| `aws_apigatewayv2_integration.lambda_proxy` | AWS_PROXY integration; forwards all requests to Lambda |
| `aws_apigatewayv2_route.get_root` | Routes `GET /` to the Lambda integration |
| `aws_apigatewayv2_stage.default` | `$default` stage with `auto_deploy = true`; live immediately |
| `aws_lambda_permission.allow_apigw` | Allows API Gateway to invoke the Lambda function |
| **Total** | **7 resources** (plus 1 data source: `archive_file`) |

---

## Step 1 — Create the project folder

```bash
mkdir -p ~/terraform-aws-lambda-029-demo/src
cd ~/terraform-aws-lambda-029-demo
```

---

## Step 2 — Write the Lambda handler

```bash
cat > src/handler.py <<'EOF_TF'
import json

def lambda_handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message": "Hello from robochef.co Lambda!",
            "owner": "saravanans",
            "path": event.get("rawPath", "/")
        })
    }
EOF_TF
```

---

## Step 3 — Write all Terraform files

### `providers.tf`

```bash
cat > providers.tf <<'EOF_TF'
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws     = { source = "hashicorp/aws",     version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.0" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Owner = var.owner, Project = var.project }
  }
}
EOF_TF
```

### `variables.tf`

```bash
cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "terraform-029"
}

variable "owner" {
  description = "Owner tag value"
  type        = string
  default     = "saravanans"
}

variable "project" {
  description = "Project tag value"
  type        = string
  default     = "robochef.co"
}

variable "lambda_runtime" {
  description = "Lambda runtime identifier"
  type        = string
  default     = "python3.12"
}

variable "lambda_handler" {
  description = "Lambda handler in the form file.function"
  type        = string
  default     = "handler.lambda_handler"
}
EOF_TF
```

### `main.tf`

```bash
cat > main.tf <<'EOF_TF'
# --- Package the Lambda source code ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/handler.zip"
}

# --- IAM: trust policy document ---
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# --- IAM: execution role ---
resource "aws_iam_role" "lambda_exec" {
  name               = "${var.name_prefix}-lambda-exec-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# --- IAM: attach managed policy for CloudWatch logs ---
resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --- Lambda function ---
resource "aws_lambda_function" "api_handler" {
  function_name    = "${var.name_prefix}-api-handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.lambda_exec.arn
  handler          = var.lambda_handler
  runtime          = var.lambda_runtime
}

# --- API Gateway v2: HTTP API ---
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.name_prefix}-http-api"
  protocol_type = "HTTP"
}

# --- API Gateway: Lambda proxy integration ---
resource "aws_apigatewayv2_integration" "lambda_proxy" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api_handler.invoke_arn
  payload_format_version = "2.0"
}

# --- API Gateway: route ---
resource "aws_apigatewayv2_route" "get_root" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_proxy.id}"
}

# --- API Gateway: $default stage with auto-deploy ---
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# --- Lambda permission: allow API Gateway to invoke the function ---
resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
EOF_TF
```

**Key points about `main.tf`:**
- `data "archive_file"` zips `src/` on every `terraform apply`; it is a data source and does not count as a managed resource
- `source_code_hash = data.archive_file.lambda_zip.output_base64sha256` tells Terraform to update the Lambda deployment package whenever the zip changes
- `payload_format_version = "2.0"` means Lambda receives the v2 event shape (`rawPath`, `rawQueryString`, `requestContext`, etc.)
- `source_arn = "${execution_arn}/*/*"` scopes the permission to this API only; wildcards cover any stage and any method

### `outputs.tf`

```bash
cat > outputs.tf <<'EOF_TF'
output "api_url" {
  description = "Invoke URL for the HTTP API"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.api_handler.function_name
}

output "lambda_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.api_handler.arn
}
EOF_TF
```

---

## Step 4 — Init, Fmt, Validate, Plan, Apply

```bash
terraform init
```

Expected output (key lines):
```
Initializing provider plugins...
- Finding hashicorp/archive versions matching "~> 2.0"...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Installing hashicorp/archive v2.x.x...
- Installing hashicorp/aws v6.x.x...

Terraform has been successfully initialized!
```

```bash
terraform fmt
terraform validate
# Success! The configuration is valid.

terraform plan
# Plan: 7 to add, 0 to change, 0 to destroy.
```

```bash
terraform apply -auto-approve
```

Expected output:
```
data.aws_iam_policy_document.lambda_assume_role: Reading...
data.archive_file.lambda_zip: Reading...
data.aws_iam_policy_document.lambda_assume_role: Read complete after 0s
data.archive_file.lambda_zip: Read complete after 0s [id=...]
aws_iam_role.lambda_exec: Creating...
aws_iam_role.lambda_exec: Creation complete after 1s [id=terraform-029-lambda-exec-role]
aws_iam_role_policy_attachment.basic: Creating...
aws_lambda_function.api_handler: Creating...
aws_iam_role_policy_attachment.basic: Creation complete after 1s
aws_apigatewayv2_api.http_api: Creating...
aws_apigatewayv2_api.http_api: Creation complete after 1s [id=p4js6mz1sj]
aws_apigatewayv2_integration.lambda_proxy: Creating...
aws_apigatewayv2_integration.lambda_proxy: Creation complete after 0s
aws_apigatewayv2_route.get_root: Creating...
aws_apigatewayv2_stage.default: Creating...
aws_apigatewayv2_route.get_root: Creation complete after 0s
aws_apigatewayv2_stage.default: Creation complete after 1s
aws_lambda_function.api_handler: Creation complete after 8s [id=terraform-029-api-handler]
aws_lambda_permission.allow_apigw: Creating...
aws_lambda_permission.allow_apigw: Creation complete after 0s

Apply complete! Resources: 7 added, 0 changed, 0 destroyed.

Outputs:

api_url              = "https://p4js6mz1sj.execute-api.ap-south-1.amazonaws.com/"
lambda_arn           = "arn:aws:lambda:ap-south-1:043000359118:function:terraform-029-api-handler"
lambda_function_name = "terraform-029-api-handler"
```

---

## Step 5 — Verify

### Call the API with curl

```bash
curl $(terraform output -raw api_url)
```

Expected response:
```json
{"message": "Hello from robochef.co Lambda!", "owner": "saravanans", "path": "/"}
```

### Confirm the Lambda function exists in AWS

```bash
aws lambda get-function \
  --function-name $(terraform output -raw lambda_function_name) \
  --query 'Configuration.[FunctionName,Runtime,State]' \
  --output table
```

Expected:
```
--------------------------------------------------------------
|                        GetFunction                         |
+-----------------------------+--------------+---------------+
|  terraform-029-api-handler  |  python3.12  |  Active       |
+-----------------------------+--------------+---------------+
```

### Invoke Lambda directly (without API Gateway)

```bash
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/response.json && cat /tmp/response.json
```

Expected:
```json
{"statusCode": 200, "headers": {"Content-Type": "application/json"}, "body": "{\"message\": \"Hello from robochef.co Lambda!\", \"owner\": \"saravanans\", \"path\": \"/\"}"}
```

---

## Key Concept 1 — `source_code_hash` and why it matters

```hcl
resource "aws_lambda_function" "api_handler" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  ...
}
```

Without `source_code_hash`, Terraform compares only the zip file path — not its contents. If you edit `handler.py` and run `terraform apply`, Terraform sees the same filename and **skips the update**. The old code stays deployed.

With `source_code_hash`, Terraform computes the SHA-256 of the zip on every plan. If the hash differs from what is stored in state, Terraform marks the Lambda as needing an update and uploads the new zip.

| Without `source_code_hash` | With `source_code_hash` |
|---------------------------|------------------------|
| Code change ignored by Terraform | Code change triggers Lambda update |
| Old function keeps running | New function deployed on next apply |
| Requires manual console redeploy | Fully automated |

---

## Key Concept 2 — API Gateway v2 (HTTP API) vs v1 (REST API)

| Feature | REST API (v1) | HTTP API (v2) |
|---------|--------------|--------------|
| Terraform resource prefix | `aws_api_gateway_*` | `aws_apigatewayv2_*` |
| Cost | Higher | ~70% cheaper |
| Latency | Higher | Lower |
| Setup complexity | More resources required | Minimal (api + integration + route + stage) |
| Stages and deployments | Manual deployment resource needed | `auto_deploy = true` on stage |
| WebSocket support | Yes | Yes |
| Payload format | 1.0 only | 1.0 or 2.0 (choose per integration) |
| Use case | Full feature set, fine-grained auth, usage plans | Simple Lambda proxy, lower cost, modern apps |

For new projects use HTTP API (v2) unless you need REST API-specific features like usage plans, API keys, or request validators.

---

## Key Concept 3 — `payload_format_version = "2.0"` and the event shape

The payload format version controls what the Lambda `event` dictionary looks like.

**Version 1.0** (legacy REST API style):
```json
{
  "httpMethod": "GET",
  "path": "/",
  "queryStringParameters": null,
  "headers": { "Host": "..." }
}
```

**Version 2.0** (HTTP API default):
```json
{
  "rawPath": "/",
  "rawQueryString": "",
  "requestContext": {
    "http": { "method": "GET", "path": "/" }
  },
  "headers": { "host": "..." }
}
```

The handler in this lab uses `event.get("rawPath", "/")` — a v2.0 field. If you switch to `payload_format_version = "1.0"`, `rawPath` will be absent and the output will fall back to `"/"` via the default.

---

## Key Concept 4 — `aws_lambda_permission` and `source_arn` scoping

Lambda function policies control **who can invoke** a function. Without a permission resource, API Gateway calls return HTTP 403.

```hcl
resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
```

The `source_arn` pattern `{execution_arn}/*/*` breaks down as:

```
arn:aws:execute-api:ap-south-1:043000359118:p4js6mz1sj/*/*
                                             ^^^^^^^^^^  ^ ^
                                             api-id      | any method
                                                         any stage
```

Scoping to a specific API ARN prevents **other** API Gateways in the account from invoking this Lambda. Omitting `source_arn` would allow any API Gateway in any account to invoke the function.

---

## Step 6 — Destroy

```bash
terraform destroy -auto-approve
rm -rf .terraform
```

Expected:
```
Destroy complete! Resources: 7 destroyed.
```

---

## Concept Summary

| Concept | Key rule |
|---------|----------|
| `archive_file` | Data source — zips your code directory; does not count as a managed resource |
| `source_code_hash` | Always set this; without it Terraform ignores code changes |
| IAM execution role | Lambda needs a role with `sts:AssumeRole` trust for `lambda.amazonaws.com` |
| `AWSLambdaBasicExecutionRole` | Minimum managed policy; grants CloudWatch Logs write access |
| HTTP API vs REST API | HTTP API is simpler and ~70% cheaper; prefer it for Lambda proxies |
| `payload_format_version` | `"2.0"` gives `rawPath`, `rawQueryString`; `"1.0"` gives `httpMethod`, `path` |
| `$default` stage + `auto_deploy` | Eliminates the manual deployment step; URL is live immediately |
| `aws_lambda_permission` | Required for API Gateway to invoke Lambda; scope `source_arn` to your API |
| `source_arn` wildcards | `/*/*` means any stage + any method for this API |
| `default_tags` on provider | Tags applied to every resource without repeating them in each block |

---

## Copy-paste script (full flow)

```bash
mkdir -p ~/terraform-aws-lambda-029-demo/src
cd ~/terraform-aws-lambda-029-demo

cat > src/handler.py <<'EOF_TF'
import json

def lambda_handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message": "Hello from robochef.co Lambda!",
            "owner": "saravanans",
            "path": event.get("rawPath", "/")
        })
    }
EOF_TF

cat > providers.tf <<'EOF_TF'
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws     = { source = "hashicorp/aws",     version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.0" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Owner = var.owner, Project = var.project }
  }
}
EOF_TF

cat > variables.tf <<'EOF_TF'
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "terraform-029"
}

variable "owner" {
  description = "Owner tag value"
  type        = string
  default     = "saravanans"
}

variable "project" {
  description = "Project tag value"
  type        = string
  default     = "robochef.co"
}

variable "lambda_runtime" {
  description = "Lambda runtime identifier"
  type        = string
  default     = "python3.12"
}

variable "lambda_handler" {
  description = "Lambda handler in the form file.function"
  type        = string
  default     = "handler.lambda_handler"
}
EOF_TF

cat > main.tf <<'EOF_TF'
# --- Package the Lambda source code ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/handler.zip"
}

# --- IAM: trust policy document ---
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# --- IAM: execution role ---
resource "aws_iam_role" "lambda_exec" {
  name               = "${var.name_prefix}-lambda-exec-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# --- IAM: attach managed policy for CloudWatch logs ---
resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --- Lambda function ---
resource "aws_lambda_function" "api_handler" {
  function_name    = "${var.name_prefix}-api-handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.lambda_exec.arn
  handler          = var.lambda_handler
  runtime          = var.lambda_runtime
}

# --- API Gateway v2: HTTP API ---
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.name_prefix}-http-api"
  protocol_type = "HTTP"
}

# --- API Gateway: Lambda proxy integration ---
resource "aws_apigatewayv2_integration" "lambda_proxy" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api_handler.invoke_arn
  payload_format_version = "2.0"
}

# --- API Gateway: route ---
resource "aws_apigatewayv2_route" "get_root" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_proxy.id}"
}

# --- API Gateway: $default stage with auto-deploy ---
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# --- Lambda permission: allow API Gateway to invoke the function ---
resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
EOF_TF

cat > outputs.tf <<'EOF_TF'
output "api_url" {
  description = "Invoke URL for the HTTP API"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.api_handler.function_name
}

output "lambda_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.api_handler.arn
}
EOF_TF

terraform init
terraform fmt
terraform validate
terraform plan
terraform apply -auto-approve

# Verify
curl $(terraform output -raw api_url)
aws lambda get-function \
  --function-name $(terraform output -raw lambda_function_name) \
  --query 'Configuration.[FunctionName,Runtime,State]' \
  --output table

# Cleanup
terraform destroy -auto-approve
rm -rf .terraform
```
