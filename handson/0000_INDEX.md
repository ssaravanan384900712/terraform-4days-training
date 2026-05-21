# Terraform 4-Day Training — Lab Index

**By: Saravanan Sundaramoorthy**

All hands-on labs in order. AWS labs are live-tested in ap-south-1 (Mumbai).

---

## Foundations (Labs 001–015) — Local / Docker / Non-AWS

| Lab | File | Project Dir | Description |
|-----|------|-------------|-------------|
| 001 | [001_Intro_Install_And_First_Resource.md](001_Intro_Install_And_First_Resource.md) | *(ad-hoc)* | Install Terraform, first `local_file` resource, init/plan/apply/destroy lifecycle |
| 002 | [002_Your_First_Variable.md](002_Your_First_Variable.md) | *(ad-hoc)* | Input variables, `var.` references, default values |
| 003 | [003_Variable_Types_And_Multiple_Resources.md](003_Variable_Types_And_Multiple_Resources.md) | *(ad-hoc)* | String/number/bool/list/map variable types, multiple resources |
| 004 | [004_Tfvars_Env_Vars_And_Precedence.md](004_Tfvars_Env_Vars_And_Precedence.md) | *(ad-hoc)* | `.tfvars`, `TF_VAR_*` env vars, variable precedence order |
| 005 | [005_Random_Provider_Statefile_Validate.md](005_Random_Provider_Statefile_Validate.md) | *(ad-hoc)* | `random` provider, statefile inspection, `terraform validate` |
| 006 | [006_Outputs_And_Terraform_Output_Command.md](006_Outputs_And_Terraform_Output_Command.md) | *(ad-hoc)* | Output values, `terraform output`, output in automation |
| 007 | [007_Sensitive_And_Validation.md](007_Sensitive_And_Validation.md) | *(ad-hoc)* | `sensitive = true`, custom variable validation rules |
| 008 | [008_Random_Provider_And_Resource_Chaining.md](008_Random_Provider_And_Resource_Chaining.md) | *(ad-hoc)* | `random_string`, chaining resource outputs as inputs |
| 009 | [009_Resource_Chaining_And_Dependency_Graph.md](009_Resource_Chaining_And_Dependency_Graph.md) | *(ad-hoc)* | Implicit vs explicit dependencies, `terraform graph` |
| 010 | [010_Terraform_Docker_Demo.md](010_Terraform_Docker_Demo.md) | *(ad-hoc)* | `docker` provider, `docker_image` + `docker_container` resources |
| 011 | [011_Dollar_Variable_Placeholder_Terraform.md](011_Dollar_Variable_Placeholder_Terraform.md) | *(ad-hoc)* | String interpolation `${}`, template expressions |
| 012 | [012_Count_Multiple_Resources.md](012_Count_Multiple_Resources.md) | *(ad-hoc)* | `count` meta-argument, `count.index`, `[*]` splat |
| 013 | [013_ForEach_Named_Resources.md](013_ForEach_Named_Resources.md) | *(ad-hoc)* | `for_each` with maps and sets, `each.key` / `each.value` |
| 014 | [014_Terraform_AWS_CLI_Configure_EC2_Instance.md](014_Terraform_AWS_CLI_Configure_EC2_Instance.md) | *(ad-hoc)* | AWS CLI setup, first EC2 instance, provider configuration |
| 014.1 | [014.1_Terraform_AWS_EC2_SSH_Key_Public_IP_Demo_Updated.md](014.1_Terraform_AWS_EC2_SSH_Key_Public_IP_Demo_Updated.md) | *(ad-hoc)* | EC2 with SSH key pair, public IP, security group |
| 015 | [015_Keepers_Controlled_Recreation.md](015_Keepers_Controlled_Recreation.md) | *(ad-hoc)* | `random_password` with `keepers`, controlled resource recreation |

---

## AWS Core Infrastructure (Labs 016–027)

| Lab | File | Project Dir | Description |
|-----|------|-------------|-------------|
| 016 | [016_Terraform_AWS_EC2_SSH_Key_Generated_By_Terraform.md](016_Terraform_AWS_EC2_SSH_Key_Generated_By_Terraform.md) | `~/terraform-aws-ec2-016-demo/` | EC2 + Terraform-generated ED25519 SSH key via `tls_private_key` |
| 017 | [017_Terraform_AWS_S3_Bucket_Objects_Put_And_Get.md](017_Terraform_AWS_S3_Bucket_Objects_Put_And_Get.md) | `~/terraform-aws-s3-017-demo/` | S3 bucket creation, `aws_s3_object` upload, `terraform output` for object URL |
| 018 | [018_Terraform_S3_Remote_State_Backend.md](018_Terraform_S3_Remote_State_Backend.md) | `~/terraform-aws-s3-backend-018-demo/` | S3 as Terraform remote state backend, `backend "s3"` config |
| 019 | [019_Terraform_DynamoDB_State_Locking_Backend.md](019_Terraform_DynamoDB_State_Locking_Backend.md) | `~/terraform-aws-dynamo-backend-019-demo/` | DynamoDB state locking, S3+DynamoDB backend combination |
| 020 | [020_Terraform_EC2_Custom_AMI_And_Instance_Launch.md](020_Terraform_EC2_Custom_AMI_And_Instance_Launch.md) | `~/terraform-aws-ami-020-demo/` | EC2 → SSH changes → `aws_ami_from_instance` → launch new EC2 from custom AMI |
| 021 | [021_Terraform_AWS_ElastiCache_Redis_Demo.md](021_Terraform_AWS_ElastiCache_Redis_Demo.md) | `~/terraform-aws-redis-021-demo/` | ElastiCache Redis cluster, `redis-cli` set/get demo |
| 022 | [022_Terraform_AWS_VPC_Subnets_And_Route_Tables.md](022_Terraform_AWS_VPC_Subnets_And_Route_Tables.md) | `~/terraform-aws-vpc-022-demo/` | Custom VPC, public/private subnets, internet gateway, route tables |
| 023 | [023_Terraform_S3_Bucket_Policies_And_Versioning.md](023_Terraform_S3_Bucket_Policies_And_Versioning.md) | `~/terraform-aws-s3-policy-023-demo/` | S3 bucket policy, versioning, lifecycle rules |
| 024 | [024_Terraform_AWS_IAM_Users_Roles_And_Policies.md](024_Terraform_AWS_IAM_Users_Roles_And_Policies.md) | `~/terraform-aws-iam-024-demo/` | IAM users, groups, roles, inline & managed policies |
| 025 | [025_Terraform_Reusable_Module_EC2_Instance.md](025_Terraform_Reusable_Module_EC2_Instance.md) | `~/terraform-modules/ec2-instance/` | Writing a reusable EC2 module with variables and outputs |
| 026 | [026_Terraform_Reusable_Module_S3_Bucket.md](026_Terraform_Reusable_Module_S3_Bucket.md) | `~/terraform-modules/s3-bucket/` | Writing a reusable S3 bucket module |
| 027 | [027_Terraform_Modules_EC2_And_S3_Demo_Project.md](027_Terraform_Modules_EC2_And_S3_Demo_Project.md) | `~/terraform-aws-modules-027-demo/` | Root module consuming both EC2 and S3 modules together |

---

## AWS Services (Labs 028–034)

| Lab | File | Project Dir | Description |
|-----|------|-------------|-------------|
| 028 | [028_Terraform_AWS_RDS_Postgres_Demo.md](028_Terraform_AWS_RDS_Postgres_Demo.md) | `~/terraform-aws-rds-028-demo/` | RDS PostgreSQL 16.14 (db.t3.micro), subnet group, security group, `psql` connect |
| 029 | [029_Terraform_AWS_Lambda_And_API_Gateway.md](029_Terraform_AWS_Lambda_And_API_Gateway.md) | `~/terraform-aws-lambda-029-demo/` | Lambda (Python 3.12) + API Gateway v2 HTTP API, `archive_file`, curl test |
| 030 | [030_Terraform_AWS_ECS_Fargate_ECR_Demo.md](030_Terraform_AWS_ECS_Fargate_ECR_Demo.md) | `~/terraform-aws-ecs-030-demo/` | ECS Fargate + ECR, ALB, CloudWatch logs (`logs:CreateLogGroup` IAM fix) |
| 031 | [031_Terraform_Import_EC2_Into_State.md](031_Terraform_Import_EC2_Into_State.md) | `~/terraform-aws-import-031-demo/` | Create EC2 via AWS CLI → `terraform import` → verify 0-change plan |
| 032 | [032_Terraform_AWS_Secrets_Manager_Demo.md](032_Terraform_AWS_Secrets_Manager_Demo.md) | `~/terraform-aws-secrets-032-demo/` | AWS Secrets Manager, secret rotation, `recovery_window_in_days = 0` for labs |
| 033 | [033_Terraform_AWS_EKS_Cluster_Creation.md](033_Terraform_AWS_EKS_Cluster_Creation.md) | `~/terraform-aws-eks-033-demo/` | EKS 1.31 cluster, managed node group (t3.small, 1 node), `aws eks update-kubeconfig` |
| 034 | [034_Terraform_Kubernetes_Resources_Via_Provider.md](034_Terraform_Kubernetes_Resources_Via_Provider.md) | `~/terraform-aws-k8s-034-demo/` | Namespace, ConfigMap, Deployment, Service via Terraform `kubernetes` provider |

---

## Terraform Language & Meta-Arguments (Labs 035–041)

| Lab | File | Project Dir | Description |
|-----|------|-------------|-------------|
| 035 | [035_Terraform_Null_Resource_Triggers_And_Depends_On.md](035_Terraform_Null_Resource_Triggers_And_Depends_On.md) | `~/terraform-null-035/` | `null_resource` triggers, `depends_on`, `terraform_data` (1.4+) replacement |
| 036 | [036_Terraform_Workspaces.md](036_Terraform_Workspaces.md) | `~/terraform-workspaces-036/` | `terraform workspace new/select/list/delete`, workspace-specific config with `lookup()` |
| 037 | [037_Terraform_Lifecycle_Meta_Arguments.md](037_Terraform_Lifecycle_Meta_Arguments.md) | `~/tf_works/037_lifecycle/` | `create_before_destroy`, `prevent_destroy`, `ignore_changes`, `replace_triggered_by` |
| 038 | [038_Terraform_Loops_For_Expressions_Dynamic_Blocks.md](038_Terraform_Loops_For_Expressions_Dynamic_Blocks.md) | `~/tf_works/038_loops/` | `for_each`, for expressions, `dynamic` blocks, `count` vs `for_each` decision |
| 039 | [039_Terraform_Conditionals_And_If_Statements.md](039_Terraform_Conditionals_And_If_Statements.md) | `~/tf_works/039_conditionals/` | `count = bool ? 1 : 0`, ternary in args, `for_each` with filter as else-if |
| 040 | [040_Terraform_Functions_Complete_Reference.md](040_Terraform_Functions_Complete_Reference.md) | `~/tf_works/040_functions/` | All 9 function categories: numeric, string, collection, encoding, filesystem, date, hash, IP, type |
| 041 | [041_Terraform_TemplateFile_Function.md](041_Terraform_TemplateFile_Function.md) | `~/terraform-templatefile-041-demo/` | `templatefile()` with `%{ for }`, `%{ if }`, nginx config generation |

---

## Provisioners & Integrations (Labs 042–043)

| Lab | File | Project Dir | Description |
|-----|------|-------------|-------------|
| 042 | [042_Terraform_Provisioners.md](042_Terraform_Provisioners.md) | `~/terraform-provisioners-042-demo/` | `local-exec`, `file`, `remote-exec` provisioners, `when = destroy`, `on_failure` |
| 043 | [043_Terraform_Ansible_Integration.md](043_Terraform_Ansible_Integration.md) | `~/terraform-aws-ansible-043-demo/` | EC2 + SSH key, `local-exec` calling `ansible-playbook`, dynamic inventory |

---

## Debugging, Testing & DRY (Labs 044–046)

| Lab | File | Project Dir | Description |
|-----|------|-------------|-------------|
| 044 | [044_Terraform_Debugging_And_Tips.md](044_Terraform_Debugging_And_Tips.md) | `/tmp/tf-debug-lab/` | `TF_LOG` levels, plan symbol analysis, `terraform console`, common error fixes |
| 045 | [045_Terraform_Testing_Manual_To_Terratest.md](045_Terraform_Testing_Manual_To_Terratest.md) | `/tmp/tf-test-lab/` `/tmp/tf-terratest-lab/` | Manual testing → `terraform test` (`.tftest.hcl`) → Terratest (Go) |
| 046 | [046_Terragrunt_DRY_Configuration.md](046_Terragrunt_DRY_Configuration.md) | `/tmp/tg-lab/` | Terragrunt `find_in_parent_folders()`, `run-all`, DRY root + child `terragrunt.hcl` |

---

## Advanced Patterns (Labs 047–051)

| Lab | File | Project Dir | Description |
|-----|------|-------------|-------------|
| 047 | [047_Terraform_Provider_Aliasing_Multi_Region.md](047_Terraform_Provider_Aliasing_Multi_Region.md) | `~/terraform-labs/047-provider-aliasing/` | Provider aliasing for multi-region (ap-south-1 + ap-southeast-1), `provider = aws.alias` |
| 048 | [048_Terraform_Zero_Downtime_Deployment.md](048_Terraform_Zero_Downtime_Deployment.md) | `~/terraform-labs/048-zero-downtime/` | `create_before_destroy`, `-/+` vs `+/-` plan symbols, zero-downtime token rotation |
| 049 | [049_Terraform_Consul_State_Backend.md](049_Terraform_Consul_State_Backend.md) | `~/terraform-labs/049-consul-backend/` | Consul backend via Docker (`bitnami/consul`), `backend "consul"`, state in KV store |
| 050 | [050_Terraform_Etcd_State_Backend.md](050_Terraform_Etcd_State_Backend.md) | `~/terraform-labs/050-etcd-backend/` | etcd backend via Docker, `backend "etcdv3"`, `ETCDCTL_API=3`, historical revision |
| 051 | [051_Terraform_HashiCorp_Vault_Integration.md](051_Terraform_HashiCorp_Vault_Integration.md) | `~/terraform-vault-051-demo/` | Vault dev server, `vault_generic_secret` data source, `sensitive = true` outputs |

---

## Reference Labs from Live Demos (Labs 052–056)

| Lab | File | Project Dir | Description |
|-----|------|-------------|-------------|
| 052 | [052_Terraform_File_Provisioner_Demo.md](052_Terraform_File_Provisioner_Demo.md) | `~/terraform-file-provisioner-052/` | `file` provisioner copies `data.txt` + `robochef_stack.sh` to AWS EC2, then `remote-exec` runs it |
| 053 | [053_Terraform_Ansible_Remote_Exec_Provisioner_Demo.md](053_Terraform_Ansible_Remote_Exec_Provisioner_Demo.md) | `~/terraform-ansible-remote-exec-053/` | AWS EC2 + `null_resource` with `file`+`remote-exec` to copy and run `robochef_stack.sh` |
| 054 | [054_GoLang_Introduction_For_Terraform_Developers.md](054_GoLang_Introduction_For_Terraform_Developers.md) | `~/go-hello-054/` | Go install, `go mod init`, `go run`, `go build`, HTTP requests, Terratest preview |
| 055 | [055_Terraform_Custom_Provider_Development.md](055_Terraform_Custom_Provider_Development.md) | `~/terraform_custom_provider_055/` `~/tf_my_custom_provider_055/` | Build custom provider binary with terraform-plugin-sdk v1, install to local plugins dir |
| 056 | [056_Terraform_Import_Existing_Resources.md](056_Terraform_Import_Existing_Resources.md) | `~/terraform-import-056/` | `terraform import` S3/VPC, import block syntax (1.5+), `-generate-config-out`, common ID formats |

---

## Local Kubernetes (Lab 057)

| Lab | File | Project Dir | Description |
|-----|------|-------------|-------------|
| 057 | [057_Terraform_Kind_Local_Kubernetes_Demo.md](057_Terraform_Kind_Local_Kubernetes_Demo.md) | `~/terraform-kind-057-demo/` | kind cluster setup, kubectl reference, Terraform kubernetes provider — namespace, configmap, deployment, service — live-tested with port-forward + scaling demo |

---

## Quick Reference

| Topic | Lab(s) |
|-------|--------|
| Variables & types | 002, 003, 004 |
| State management | 005, 018, 019, 049, 050 |
| Remote backends | 018 (S3), 019 (DynamoDB), 049 (Consul), 050 (etcd) |
| Modules | 025, 026, 027 |
| Loops | 012 (count), 013 (for_each), 038 (for expressions, dynamic) |
| Conditionals | 039 |
| Lifecycle | 037, 048 (zero-downtime) |
| Provisioners | 042, 043, 052, 053 |
| Import | 031, 056 |
| Testing | 044, 045 |
| Workspaces | 036 |
| Functions | 040, 041 |
| Security | 007 (sensitive), 024 (IAM), 032 (Secrets Manager), 051 (Vault) |
| Containers | 010 (Docker), 030 (ECS Fargate), 033 (EKS), 034 (k8s EKS), 057 (k8s kind local) |
| Serverless | 029 (Lambda + API Gateway) |
| Networking | 022 (VPC), 016/020 (EC2) |
| Custom tooling | 046 (Terragrunt), 054 (GoLang), 055 (Custom Provider) |

---

*All labs use `Owner = "saravanans"` and `Project = "robochef.co"` or `"chillbotindia.com"` as resource tags.*
*AWS region: ap-south-1 (Mumbai) throughout.*
