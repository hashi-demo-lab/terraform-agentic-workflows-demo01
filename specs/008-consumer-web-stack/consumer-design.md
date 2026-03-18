# Consumer Design: Web Application Stack

**Branch**: feat/008-consumer-web-stack
**Date**: 2026-03-18
**Status**: Draft
**Provider**: hashicorp/aws ~> 6.19
**Terraform**: >= 1.14
**HCP Terraform Org**: hashi-demos-apj

---

## Table of Contents

1. [Purpose & Requirements](#1-purpose--requirements)
2. [Module Selection & Architecture](#2-module-selection--architecture)
3. [Module Wiring](#3-module-wiring)
4. [Security Controls](#4-security-controls)
5. [Implementation Checklist](#5-implementation-checklist)
6. [Open Questions](#6-open-questions)

---

## 1. Purpose & Requirements

This deployment provisions a multi-tier web application stack in AWS ap-southeast-2 (Sydney) for a development environment. The stack provides load-balanced HTTP compute backed by persistent storage, asynchronous messaging, and operational monitoring. It supports a web application requiring an HTTP endpoint fronted by a load balancer, a database table for application state, a message queue for background processing, and alerting for operational health. The deployment targets the `hashi-demos-apj` HCP Terraform organization's sandbox project for iterative development.

**Scope boundary**: This deployment does NOT include HTTPS/TLS termination, DNS configuration, custom domain names, auto-scaling, CI/CD pipelines, application deployment, VPC creation (uses existing VPC), IAM user management, or production hardening (deletion protection, multi-AZ compute redundancy). KMS customer-managed keys are out of scope -- service-managed encryption is used throughout.

### Requirements

**Functional requirements** -- what the deployment must provision:

- FR-1: The deployment must provision a publicly accessible HTTP load balancer distributing traffic across at least 2 availability zones
- FR-2: The deployment must provision a single compute instance running an HTTP server on port 80, registered as a target behind the load balancer
- FR-3: The deployment must provision an object storage bucket with versioning and server-side encryption for ALB access log delivery
- FR-4: The deployment must provision a key-value database table with a string partition key, on-demand billing, point-in-time recovery, and server-side encryption
- FR-5: The deployment must provision a message queue with managed encryption, 4-day retention, 30-second visibility timeout, and a dead-letter queue with a max receive count of 5
- FR-6: The deployment must provision a notification topic for operational alerts
- FR-7: The deployment must provision metric-based alarms for load balancer 5xx errors (threshold 10, 2 evaluation periods, 5-minute period) and queue depth (threshold 100, 2 evaluation periods, 5-minute period), both routing to the notification topic
- FR-8: The deployment must provision a security group allowing HTTP ingress from the VPC CIDR and all egress for the compute instance
- FR-9: The deployment must use an existing VPC and its public subnets (at least 2 subnets across 2 AZs) via data source lookups

**Non-functional requirements** -- constraints:

- NFR-1: All resources must be deployed in the ap-southeast-2 (Sydney) region
- NFR-2: Monthly infrastructure cost must remain under $100 for the development environment (target ~$45/mo)
- NFR-3: All resources must be tagged with Environment, Project, ManagedBy, Application, and Owner for cost allocation and operational identification
- NFR-4: All infrastructure must be provisioned exclusively via private registry modules -- no raw infrastructure resources
- NFR-5: Provider authentication must use HCP Terraform dynamic credentials -- no static AWS keys
- NFR-6: All data-at-rest must be encrypted using service-managed encryption
- NFR-7: The deployment must be fully destroyable without manual intervention (dev environment -- deletion protection disabled, force destroy enabled)
- NFR-8: Compute instances must enforce IMDSv2 for metadata access

### Cost Constraints

| Constraint | Value |
|------------|-------|
| Monthly budget target | ~$45 (estimated $43-48/mo at on-demand pricing) |
| Enforcement mode | Advisory |
| Cost allocation tags | Environment, Project, ManagedBy, Application, Owner |
| Provider account mapping | `data.aws_caller_identity.current` for org-specific Cloudability pricing |

Cloudability Run Task is configured globally at advisory level in the hashi-demos-apj organization. It executes post-plan on every workspace run, providing cost visibility without blocking applies. The `aws_caller_identity` data source is included to enable organization-negotiated pricing in cost estimates.

---

## 2. Module Selection & Architecture

### Architectural Decisions

**Existing VPC via data sources**: Use `data.aws_vpc` and `data.aws_subnets` to look up the existing VPC and public subnets rather than creating a new VPC.
*Rationale*: The requirements explicitly state "use an existing VPC." Research (research-private-modules.md, VPC module note) confirms that when a VPC already exists, data sources should be used instead of the VPC module. Data sources are permitted in consumer code for lookups.
*Rejected*: Creating a new VPC via the VPC module -- unnecessary cost and complexity; existing VPC already has the required public subnet topology.

**ALB-managed security group for load balancer**: Use the ALB module's built-in security group creation (`create_security_group = true`) instead of a separate security group module for the ALB.
*Rationale*: Research (research-module-wiring.md, Section 7) confirms the ALB module v10.1.0 creates its own security group with configurable ingress/egress rules. This reduces module count and avoids cross-module SG wiring for the ALB. The separate security group module is used only for the EC2 instance where the requirements specify VPC CIDR-scoped ingress.
*Rejected*: Separate security group module for ALB -- adds unnecessary indirection when the ALB module handles this natively.

**Standalone security group module for EC2**: Use the private registry security group module for the EC2 instance's security group.
*Rationale*: Research (research-private-modules.md, Security Group module) confirms v5.3.1 supports predefined rules (`http-80-tcp`) and CIDR-based ingress, matching the requirement for HTTP from VPC CIDR. The EC2 module can also create its own SG, but using the standalone module gives explicit control over the ingress source CIDR.
*Rejected*: EC2 module's built-in SG -- less explicit control over ingress CIDR rules; inline SG creation does not support predefined rule names.

**Single EC2 instance via ec2-instance module**: Use the EC2 instance module for a single compute instance rather than an auto-scaling group.
*Rationale*: Requirements specify a single instance for the dev environment. Research (research-private-modules.md, EC2 module) confirms v6.1.4 supports `target_id` passthrough for ALB target group attachment. The autoscaling module (v9.0.2) is available but adds unnecessary complexity for a single-instance dev stack.
*Rejected*: Autoscaling module -- over-engineered for a single dev instance; requirements do not call for scaling.

**ALB target attachment via module input**: Wire the EC2 instance ID directly into the ALB module's `target_groups` map via `target_id` + `create_attachment = true`.
*Rationale*: Research (research-module-wiring.md, Section 2) confirms the ALB module supports direct target attachment within the `target_groups` input map, eliminating the need for a separate `aws_lb_target_group_attachment` resource. This is the recommended pattern for single-instance targets.
*Rejected*: Separate `aws_lb_target_group_attachment` resource -- prohibited as a raw resource by the consumer constitution.

**SQS module with built-in DLQ**: Use the SQS module's `create_dlq = true` flag for the dead-letter queue rather than two separate SQS module calls.
*Rationale*: Research (research-private-modules.md, SQS module) confirms v5.1.0 supports `create_dlq` with automatic redrive policy wiring. This simplifies the composition and avoids circular dependency issues between main queue and DLQ.
*Rejected*: Two separate SQS module instances -- introduces circular wiring complexity (DLQ needs main queue ARN for allow policy, main queue needs DLQ ARN for redrive policy); single module handles this internally.

**CloudWatch metric-alarm submodule**: Use the CloudWatch module's `metric-alarm` submodule for both alarms rather than raw `aws_cloudwatch_metric_alarm` resources.
*Rationale*: Research (research-private-modules.md, CloudWatch module) confirms v5.7.2 provides the `metric-alarm` submodule with inputs matching the alarm requirements (namespace, metric_name, dimensions, alarm_actions, threshold, evaluation_periods, period).
*Rejected*: Raw `aws_cloudwatch_metric_alarm` resources -- prohibited by consumer constitution.

**AWS provider >= 6.19**: Pin the AWS provider at `~> 6.19` to satisfy the minimum version requirement across all modules.
*Rationale*: Research (research-private-modules.md, Provider Version Requirements) identifies ALB v10.1.0 as requiring `>= 6.19`, which is the highest minimum across all selected modules. DynamoDB requires `>= 6.13`, SNS requires `>= 6.9`, S3 requires `>= 6.5`.
*Rejected*: Lower provider versions -- would fail module compatibility checks. Higher pinning (e.g., `~> 6.36`) -- unnecessarily restrictive.

**S3 module log delivery policies**: Use `attach_lb_log_delivery_policy = true` and `attach_elb_log_delivery_policy = true` on the S3 module for ALB access log delivery.
*Rationale*: Research (research-module-wiring.md, Section 2 and research-aws-architecture.md, Section 2) confirms these flags automatically configure the correct bucket policies for ALB log delivery, including the region-specific ELB service account. This avoids raw `aws_s3_bucket_policy` resources.
*Rejected*: Manual bucket policy via raw resource -- prohibited by consumer constitution; module handles this natively.

### Module Inventory

| Module | Registry Source | Version | Purpose | Conditional | Key Inputs | Key Outputs |
|--------|---------------|---------|---------|-------------|------------|-------------|
| alb | app.terraform.io/hashi-demos-apj/alb/aws | ~> 10.1 | Application load balancer with HTTP listener, target group, and access logging | always | `name`, `vpc_id`, `subnets`, `listeners`, `target_groups`, `access_logs`, `enable_deletion_protection`, `security_group_ingress_rules`, `security_group_egress_rules` | `arn_suffix`, `dns_name`, `security_group_id` |
| ec2_instance | app.terraform.io/hashi-demos-apj/ec2-instance/aws | ~> 6.1 | Single EC2 web server instance with HTTP user data | always | `name`, `instance_type`, `subnet_id`, `vpc_security_group_ids`, `user_data`, `associate_public_ip_address` | `id`, `public_ip`, `private_ip` |
| ec2_sg | app.terraform.io/hashi-demos-apj/security-group/aws | ~> 5.3 | Security group for EC2 -- HTTP from VPC CIDR, all egress | always | `name`, `vpc_id`, `ingress_rules`, `ingress_cidr_blocks`, `egress_rules` | `security_group_id` |
| s3_bucket | app.terraform.io/hashi-demos-apj/s3-bucket/aws | ~> 6.0 | S3 bucket for ALB access logs with versioning and encryption | always | `bucket`, `environment`, `versioning`, `server_side_encryption_configuration`, `force_destroy`, `attach_lb_log_delivery_policy`, `attach_elb_log_delivery_policy` | `s3_bucket_id`, `s3_bucket_arn` |
| dynamodb_table | app.terraform.io/hashi-demos-apj/dynamodb-table/aws | ~> 5.2 | DynamoDB table for application state | always | `name`, `hash_key`, `attributes`, `billing_mode`, `point_in_time_recovery_enabled`, `server_side_encryption_enabled`, `deletion_protection_enabled` | `dynamodb_table_arn`, `dynamodb_table_id` |
| sqs | app.terraform.io/hashi-demos-apj/sqs/aws | ~> 5.1 | SQS queue with DLQ for background message processing | always | `name`, `visibility_timeout_seconds`, `message_retention_seconds`, `sqs_managed_sse_enabled`, `create_dlq`, `redrive_policy` | `queue_arn`, `queue_url`, `queue_name`, `dead_letter_queue_arn`, `dead_letter_queue_url` |
| sns | app.terraform.io/hashi-demos-apj/sns/aws | ~> 7.0 | SNS topic for operational alert routing | always | `name`, `display_name` | `topic_arn` |
| alb_5xx_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | CloudWatch alarm for ALB 5xx error rate | always | `alarm_name`, `namespace`, `metric_name`, `dimensions`, `threshold`, `evaluation_periods`, `period`, `statistic`, `comparison_operator`, `alarm_actions`, `ok_actions`, `treat_missing_data` | `cloudwatch_metric_alarm_arn` |
| sqs_depth_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | CloudWatch alarm for SQS queue depth | always | `alarm_name`, `namespace`, `metric_name`, `dimensions`, `threshold`, `evaluation_periods`, `period`, `statistic`, `comparison_operator`, `alarm_actions`, `ok_actions`, `treat_missing_data` | `cloudwatch_metric_alarm_arn` |

### Glue Resources

| Resource Type | Logical Name | Purpose | Depends On |
|---------------|-------------|---------|------------|
| random_string | suffix | Generate globally unique S3 bucket name suffix (8 chars, lowercase, no special) | -- |

Data sources (permitted in consumer code for lookups):

- `data.aws_vpc.selected` -- look up existing VPC by tag Name or default VPC
- `data.aws_subnets.public` -- look up public subnets in the selected VPC
- `data.aws_caller_identity.current` -- provide AWS account ID for Cloudability cost mapping

### Workspace Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| Organization | hashi-demos-apj | HCP Terraform organization |
| Project | sandbox (prj-QueMgU3LXgV2Ag7s) | Development project |
| Workspace | sandbox_consumer_web_stack | Must be created via API before `terraform init` |
| Execution Mode | Remote | CLI-driven runs, matches sandbox pattern |
| Terraform Version | >= 1.14 | Pinned in workspace at 1.14.7 |
| Auto Apply | false | Manual confirmation for safety |
| Allow Destroy Plan | true | Required for sandbox cleanup |
| Variable Sets | agent_AWS_Dynamic_Creds | Dynamic AWS credentials via OIDC (project-scoped) |
| VCS Connection | None | CLI-driven workflow |
| Run Tasks | Apptio-Cloudability (global, advisory, post_plan) | Cost visibility without blocking |

---

## 3. Module Wiring

### Wiring Diagram

```
data.aws_vpc.selected.id              ──> module.alb (vpc_id)
data.aws_vpc.selected.id              ──> module.ec2_sg (vpc_id)
data.aws_vpc.selected.cidr_block       ──> module.ec2_sg (ingress_cidr_blocks)
data.aws_subnets.public.ids            ──> module.alb (subnets)
data.aws_subnets.public.ids[0]         ──> module.ec2_instance (subnet_id)

module.ec2_instance.id                 ──> module.alb (target_groups.web.target_id)
module.ec2_sg.security_group_id        ──> module.ec2_instance (vpc_security_group_ids)

module.s3_bucket.s3_bucket_id          ──> module.alb (access_logs.bucket)

module.alb.arn_suffix                  ──> module.alb_5xx_alarm (dimensions.LoadBalancer)
module.sqs.queue_name                  ──> module.sqs_depth_alarm (dimensions.QueueName)

module.sns.topic_arn                   ──> module.alb_5xx_alarm (alarm_actions)
module.sns.topic_arn                   ──> module.sqs_depth_alarm (alarm_actions)
module.sns.topic_arn                   ──> module.alb_5xx_alarm (ok_actions)
module.sns.topic_arn                   ──> module.sqs_depth_alarm (ok_actions)
```

### Wiring Table

| Source Module | Output | Target Module | Input | Type | Transformation |
|--------------|--------|--------------|-------|------|----------------|
| data.aws_vpc.selected | id | alb | vpc_id | string | direct |
| data.aws_vpc.selected | id | ec2_sg | vpc_id | string | direct |
| data.aws_vpc.selected | cidr_block | ec2_sg | ingress_cidr_blocks | string -> list(string) | wrap: `[data.aws_vpc.selected.cidr_block]` |
| data.aws_subnets.public | ids | alb | subnets | list(string) | direct |
| data.aws_subnets.public | ids[0] | ec2_instance | subnet_id | string | index: `data.aws_subnets.public.ids[0]` |
| ec2_instance | id | alb | target_groups.web.target_id | string | direct (nested in target_groups map) |
| ec2_sg | security_group_id | ec2_instance | vpc_security_group_ids | string -> list(string) | wrap: `[module.ec2_sg.security_group_id]` |
| s3_bucket | s3_bucket_id | alb | access_logs.bucket | string | direct (bucket name, not ARN) |
| alb | arn_suffix | alb_5xx_alarm | dimensions.LoadBalancer | string | direct (nested in dimensions map) |
| sqs | queue_name | sqs_depth_alarm | dimensions.QueueName | string | direct (nested in dimensions map) |
| sns | topic_arn | alb_5xx_alarm | alarm_actions | string -> list(string) | wrap: `[module.sns.topic_arn]` |
| sns | topic_arn | sqs_depth_alarm | alarm_actions | string -> list(string) | wrap: `[module.sns.topic_arn]` |
| sns | topic_arn | alb_5xx_alarm | ok_actions | string -> list(string) | wrap: `[module.sns.topic_arn]` |
| sns | topic_arn | sqs_depth_alarm | ok_actions | string -> list(string) | wrap: `[module.sns.topic_arn]` |

### Provider Configuration

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      Application = var.application_name
    }
  }

  # Dynamic credentials via HCP Terraform
  # agent_AWS_Dynamic_Creds variable set injects:
  #   TFC_AWS_PROVIDER_AUTH = true
  #   TFC_AWS_RUN_ROLE_ARN = arn:aws:iam::855831148133:role/tfstacks-role
  #   TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE = aws.workload.identity
}
```

### Variables

| Variable | Type | Required | Default | Validation | Sensitive | Description |
|----------|------|----------|---------|------------|-----------|-------------|
| aws_region | string | No | "ap-southeast-2" | Must match `^[a-z]{2}-[a-z]+-[0-9]$` | No | AWS region for all resources |
| project_name | string | No | "web-stack" | Length 1-32 | No | Project name used in resource naming and tags |
| environment | string | No | "dev" | Must be one of: dev, staging, prod | No | Deployment environment |
| owner | string | Yes | -- | Length >= 1 | No | Resource owner for tagging and accountability |
| application_name | string | No | "web-app" | Length 1-64 | No | Application name for tagging |
| name_prefix | string | No | "" | Length <= 20 | No | Name prefix for resources; defaults to `{project_name}-{environment}` via locals if empty |
| instance_type | string | No | "t3.small" | Must match `^t[23]\.(micro\|small\|medium)$` | No | EC2 instance type for the web server |
| vpc_name | string | No | "" | -- | No | VPC Name tag to filter by; if empty, uses default VPC |
| user_data | string | No | (httpd install script) | -- | No | EC2 user data script for instance bootstrap |

### Outputs

| Output | Type | Source | Description |
|--------|------|--------|-------------|
| alb_dns_name | string | module.alb.dns_name | DNS name of the application load balancer |
| alb_arn | string | module.alb.arn | ARN of the application load balancer |
| ec2_instance_id | string | module.ec2_instance.id | EC2 instance ID |
| ec2_public_ip | string | module.ec2_instance.public_ip | EC2 instance public IP address |
| s3_bucket_name | string | module.s3_bucket.s3_bucket_id | S3 bucket name for ALB access logs |
| s3_bucket_arn | string | module.s3_bucket.s3_bucket_arn | S3 bucket ARN |
| dynamodb_table_name | string | module.dynamodb_table.dynamodb_table_id | DynamoDB table name |
| dynamodb_table_arn | string | module.dynamodb_table.dynamodb_table_arn | DynamoDB table ARN |
| sqs_queue_url | string | module.sqs.queue_url | SQS queue URL |
| sqs_queue_arn | string | module.sqs.queue_arn | SQS queue ARN |
| sqs_dlq_url | string | module.sqs.dead_letter_queue_url | SQS dead-letter queue URL |
| sns_topic_arn | string | module.sns.topic_arn | SNS topic ARN for operational alerts |
| vpc_id | string | data.aws_vpc.selected.id | VPC ID used by the deployment |

---

## 4. Security Controls

| Control | Enforcement | Module Config | Reference |
|---------|-------------|---------------|-----------|
| Encryption at rest -- S3 | Module default + explicit config. S3 module defaults to BucketOwnerEnforced with public access blocks. AES256 SSE configured explicitly. | s3_bucket: `server_side_encryption_configuration = { rule = { apply_server_side_encryption_by_default = { sse_algorithm = "AES256" } } }` | CIS AWS 2.1.1 -- S3 bucket server-side encryption enabled |
| Encryption at rest -- DynamoDB | Explicit enable. Module defaults `server_side_encryption_enabled = false`; consumer sets to `true`. | dynamodb_table: `server_side_encryption_enabled = true` | CIS AWS 3.2 -- DynamoDB table encryption enabled |
| Encryption at rest -- SQS | Module default. SQS module defaults `sqs_managed_sse_enabled = true` for both main queue and DLQ. | sqs: `sqs_managed_sse_enabled = true` (default honoured) | CIS AWS 2.3 -- SQS queue encryption enabled |
| Encryption in transit -- ALB | Module default. ALB module defaults `drop_invalid_header_fields = true`. HTTP-only listener for dev. | alb: `drop_invalid_header_fields = true` (default honoured). `[SECURITY OVERRIDE]` HTTP listener without TLS -- justified: dev environment, no sensitive data in transit, no domain/certificate available. | AWS Well-Architected SEC09-BP02 -- Enforce encryption in transit. Override accepted for dev. |
| Public access -- S3 | Module default. S3 module defaults all public access blocks to `true` (`block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets`). | s3_bucket: all public access block defaults honoured | CIS AWS 2.1.2 -- S3 bucket public access blocked |
| Public access -- EC2 | `[SECURITY OVERRIDE]` EC2 instance has `associate_public_ip_address = true` and is placed in a public subnet. Justified: dev environment requires direct HTTP access; ALB in public subnets requires targets to be reachable. Security group limits ingress to VPC CIDR only on port 80. | ec2_instance: `associate_public_ip_address = true` | AWS Well-Architected SEC05-BP01 -- Create network layers. Override accepted for dev; production should use private subnets with NAT. |
| Public access -- ALB | ALB is internet-facing by design (public load balancer). Security group limits ingress to port 80 only. | alb: `internal = false` (default), `security_group_ingress_rules` restricted to port 80 | AWS Well-Architected SEC05-BP02 -- Control traffic flow |
| IAM least privilege | EC2 module defaults `create_iam_instance_profile = false`. No IAM role is created for the instance. Dynamic provider credentials use a scoped IAM role via OIDC. | ec2_instance: `create_iam_instance_profile = false` (default honoured). Provider auth via `tfstacks-role` scoped to sandbox resources. | CIS AWS 1.16 -- IAM policies attached only to groups or roles |
| IMDSv2 enforcement | Module default. EC2 module defaults `metadata_options` to `http_tokens = "required"` and `http_put_response_hop_limit = 1`. | ec2_instance: IMDSv2 defaults honoured | CIS AWS 5.6 -- IMDSv2 required on EC2 instances |
| Logging -- ALB access logs | Explicit enable. ALB access logs sent to S3 bucket with proper delivery policies. | alb: `access_logs = { bucket = module.s3_bucket.s3_bucket_id, enabled = true, prefix = "alb" }`. s3_bucket: `attach_lb_log_delivery_policy = true`, `attach_elb_log_delivery_policy = true` | AWS Well-Architected SEC04-BP01 -- Configure service and application logging |
| Deletion protection -- ALB | `[SECURITY OVERRIDE]` Deletion protection disabled. Justified: dev/sandbox environment must be fully destroyable without manual intervention (NFR-7). | alb: `enable_deletion_protection = false` | AWS Well-Architected REL09-BP01 -- Back up data. Override accepted for dev. |
| Deletion protection -- DynamoDB | `[SECURITY OVERRIDE]` Deletion protection disabled. Justified: dev/sandbox environment (NFR-7). | dynamodb_table: `deletion_protection_enabled = false` | AWS Well-Architected REL09-BP01. Override accepted for dev. |
| Tagging | Provider `default_tags` propagates 5 tags (Project, Environment, ManagedBy, Owner, Application) to all resources. Module-specific tags supplement where needed. | provider: `default_tags` block. Modules: `tags` input for supplemental tags. | AWS Well-Architected COST02-BP01 -- Define a tagging schema |

---

## 5. Implementation Checklist

- [x] **A: Scaffold** -- Create project file structure. Files: `versions.tf` (terraform block with required_version + required_providers for aws and random), `backend.tf` (cloud block for hashi-demos-apj/sandbox_consumer_web_stack), `providers.tf` (AWS provider with region and default_tags), `variables.tf` (all 9 variables from the Variables table with types, defaults, descriptions, and validation blocks), `outputs.tf` (all 13 outputs with descriptions), `locals.tf` (name_prefix computation, common_tags, user_data default, vpc/subnet local aliases), `data.tf` (data.aws_vpc.selected, data.aws_subnets.public, data.aws_caller_identity.current)
- [x] **B: Core infrastructure modules** -- Add module calls for networking and compute in `main.tf`. Modules: `ec2_sg` (security group with HTTP/VPC CIDR ingress, all egress), `s3_bucket` (versioning, AES256 SSE, force_destroy, LB log delivery policies), `alb` (HTTP listener port 80, target group with EC2 instance, access logs to S3, deletion protection disabled, security group ingress/egress rules). Glue: `random_string.suffix` for S3 bucket naming.
- [x] **C: Compute and data modules** -- Add module calls for EC2 and data tier in `main.tf`. Modules: `ec2_instance` (t3.small, first public subnet, user_data, public IP, security group wired), `dynamodb_table` (hash key "id", PAY_PER_REQUEST, PITR, SSE, deletion protection disabled), `sqs` (managed SSE, 4-day retention, 30s visibility, DLQ with max receive 5).
- [x] **D: Monitoring and alerting modules** -- Add module calls for monitoring in `main.tf`. Modules: `sns` (notification topic), `alb_5xx_alarm` (metric-alarm submodule for ALB 5xx, wired to ALB arn_suffix and SNS topic_arn), `sqs_depth_alarm` (metric-alarm submodule for SQS depth, wired to SQS queue_name and SNS topic_arn).
- [x] **E: Wiring verification and polish** -- Verify all cross-module references match the wiring table. Create `terraform.auto.tfvars.example` with example values. Create `README.md` with deployment instructions. Run `terraform fmt`, `terraform validate`, `tflint`, and `trivy config .` to verify compliance.

---

## 6. Open Questions

No open questions. All requirements were resolved during Phase 1 clarification. Key assumptions documented:

- **VPC lookup strategy**: If `vpc_name` is empty, the deployment uses the default VPC (`default = true` on the data source). If provided, it filters by `tag:Name`. This handles both default-VPC and tagged-VPC scenarios without ambiguity.
- **EC2 AMI**: The EC2 module defaults to Amazon Linux 2023 via SSM parameter (`/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64`). No explicit AMI variable is needed.
- **ALB security group scope**: The ALB accepts HTTP from `0.0.0.0/0` (internet-facing) since it is a public load balancer. The EC2 security group restricts ingress to VPC CIDR only, providing a layered security approach.
- **SQS DLQ retention**: The DLQ uses the SQS module's default retention (14 days), which is longer than the main queue's 4-day retention, ensuring failed messages are preserved for investigation.
