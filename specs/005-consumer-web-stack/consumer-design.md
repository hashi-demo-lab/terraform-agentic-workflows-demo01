# Consumer Design: Web Application Stack

**Branch**: feat/005-consumer-web-stack
**Date**: 2026-03-17
**Status**: Draft
**Provider**: aws ~> 6.19
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

This deployment provisions a complete web application stack in the ap-southeast-2 (Sydney) region for a development environment. It composes networking, compute, storage, data, messaging, and monitoring infrastructure from private registry modules to support a simple HTTP-serving application behind a load balancer. The stack provides a functional baseline that mirrors production architecture topology at minimal cost, enabling developers to iterate on application code and infrastructure changes with full observability.

**Scope boundary**: This deployment does NOT create a new VPC -- it references an existing VPC and its public subnets via data sources. HTTPS/TLS termination, ACM certificates, Route53 DNS records, Auto Scaling Groups, CI/CD pipelines, and application deployment automation are explicitly out of scope. No production workloads will run on this stack.

### Requirements

**Functional requirements** -- what the deployment must provision:

- FR-1: The deployment must reference an existing VPC and discover at least 2 public subnets across 2 availability zones via data source lookups.
- FR-2: The deployment must provision a publicly accessible application load balancer in the discovered public subnets with an HTTP listener on port 80 that forwards traffic to a target group.
- FR-3: The deployment must provision a single compute instance (t3.small) in the first public subnet with a user data script that serves HTTP responses on port 80, registered as a target in the load balancer target group.
- FR-4: The deployment must provision a security group for the compute instance allowing HTTP (port 80) ingress from the VPC CIDR block and all egress.
- FR-5: The deployment must provision an S3 bucket with versioning enabled, AES256 server-side encryption, force destroy enabled, and ELB/LB log delivery policies attached to receive ALB access logs.
- FR-6: The deployment must provision a DynamoDB table with a string hash key (`id`), on-demand billing (PAY_PER_REQUEST), point-in-time recovery enabled, and server-side encryption enabled.
- FR-7: The deployment must provision an SQS queue with managed SSE, 4-day message retention, 30-second visibility timeout, and a dead-letter queue with a max receive count of 5.
- FR-8: The deployment must provision an SNS topic for operational alerts.
- FR-9: The deployment must provision CloudWatch metric alarms for ALB 5xx errors (threshold 10, 2 evaluation periods, 5-minute period) and SQS queue depth (threshold 100, 2 evaluation periods, 5-minute period), both routing to the SNS topic.
- FR-10: All resources must be tagged with Environment, Project, ManagedBy (terraform), and Application via provider default tags.

**Non-functional requirements** -- constraints:

- NFR-1: All infrastructure must be provisioned via private registry modules from `hashi-demos-apj` -- no raw resource blocks except permitted glue resources.
- NFR-2: The deployment targets a development environment with minimal cost; deletion protection must be disabled on ALB, DynamoDB, and S3 (force destroy) to support clean teardown.
- NFR-3: The deployment must execute via HCP Terraform remote execution with dynamic provider credentials -- no static AWS credentials in code.
- NFR-4: AWS provider version must satisfy all module constraints (minimum >= 6.19 per ALB module requirement).
- NFR-5: Resource naming must follow the `{name_prefix}-{environment}` pattern for consistency and environment promotion.

### Cost Constraints

| Constraint | Value |
|------------|-------|
| Monthly budget target | N/A (dev environment, estimated ~$45-50/month without NAT Gateway) |
| Enforcement mode | Advisory |
| Cost allocation tags | Environment, Project, ManagedBy, Application |
| Provider account mapping | `aws_caller_identity` data source for org-specific Cloudability pricing |

Cost governance is configured via Cloudability Run Task at `post_plan` stage in advisory mode. This provides cost feedback to engineers without blocking development deployments. The `aws_caller_identity` data source enables organization-specific pricing rather than public list prices (per `research-cost-governance.md` findings).

---

## 2. Module Selection & Architecture

### Architectural Decisions

**Use existing VPC via data sources instead of VPC module**: Reference the existing VPC and public subnets using `data.aws_vpc` and `data.aws_subnets` data sources.
*Rationale*: The requirements explicitly state "do NOT create a new VPC." Data sources are the canonical way to reference existing infrastructure without managing it (per `research-aws-architecture.md` finding #1). The VPC module (v6.5.0) is available but unnecessary for this use case.
*Rejected*: Creating a new VPC via the `vpc` module -- out of scope per requirements; would add NAT Gateway cost (~$34.50/month).

**Single EC2 instance via ec2-instance module instead of Auto Scaling Group**: Provision a single t3.small instance for the development workload.
*Rationale*: The requirements specify a single EC2 instance. The `ec2-instance` module (v6.1.4) is purpose-built for this scenario. The `autoscaling` module (v9.0.2) is available but adds unnecessary complexity for a single dev instance (per `research-private-modules.md` alternatives analysis).
*Rejected*: Auto Scaling Group via `autoscaling` module -- overkill for single dev instance; adds launch template complexity.

**Separate security group module for EC2 instead of ALB built-in SG**: Use the standalone `security-group` module for the EC2 instance security group while letting the ALB module create its own security group.
*Rationale*: The ALB module (v10.1.0) has built-in security group creation (`create_security_group = true`) which simplifies ALB SG management. The EC2 security group has distinct rules (VPC CIDR ingress on port 80) that are best managed separately via the `security-group` module (per `research-module-wiring.md` alternatives analysis). Using the standalone module also allows the EC2 instance module to disable its own SG creation and consume the external SG.
*Rejected*: Using the ALB module's SG for EC2 too -- different ingress requirements; tighter security with separate SGs.

**ALB built-in target group attachment (Pattern A) for EC2 wiring**: Use the ALB module's `target_groups` map with `target_id` pointing directly to the EC2 instance ID.
*Rationale*: For a single-instance stack, Pattern A (built-in attachment) is the simplest approach with no glue resources needed. The ALB module v10.1.0 supports `target_id` directly in the `target_groups` configuration (per `research-module-wiring.md` section 4, Pattern A recommendation).
*Rejected*: Pattern B (`additional_target_group_attachments`) -- designed for multi-instance; unnecessary complexity. Pattern C (raw `aws_lb_target_group_attachment`) -- prohibited by constitution as raw resource.

**CloudWatch metric-alarm submodule for each alarm**: Use the `cloudwatch//modules/metric-alarm` submodule path for each individual alarm.
*Rationale*: The CloudWatch module is submodule-based -- the root module has no inputs/outputs. Each alarm requires a separate module call using the `//modules/metric-alarm` path (per `research-private-modules.md` finding for CloudWatch module).
*Rejected*: Root CloudWatch module call -- has no inputs/outputs; must use submodules.

**AWS provider pinned to ~> 6.19**: Satisfy all private registry module version constraints with a single provider version.
*Rationale*: The ALB module (v10.1.0) has the highest minimum AWS provider requirement at >= 6.19. All other modules have lower requirements (per `research-private-modules.md` provider version compatibility table). Using `~> 6.19` satisfies all constraints while allowing patch updates.
*Rejected*: `~> 5.0` -- incompatible with all private registry modules which require >= 6.x. `~> 6.0` -- would technically work but `~> 6.19` documents the actual floor.

### Module Inventory

| Module | Registry Source | Version | Purpose | Conditional | Key Inputs | Key Outputs |
|--------|---------------|---------|---------|-------------|------------|-------------|
| alb | app.terraform.io/hashi-demos-apj/alb/aws | ~> 10.1 | Application Load Balancer with HTTP listener, target group, security group, and access logging | always | `name`, `vpc_id`, `subnets`, `listeners`, `target_groups`, `access_logs`, `enable_deletion_protection` | `arn_suffix`, `dns_name`, `security_group_id`, `target_groups` |
| ec2_web | app.terraform.io/hashi-demos-apj/ec2-instance/aws | ~> 6.1 | Single EC2 instance running HTTP application | always | `name`, `instance_type`, `subnet_id`, `vpc_security_group_ids`, `user_data`, `associate_public_ip_address` | `id`, `public_ip`, `private_ip` |
| ec2_sg | app.terraform.io/hashi-demos-apj/security-group/aws | ~> 5.3 | Security group for EC2: HTTP ingress from VPC CIDR, all egress | always | `name`, `vpc_id`, `ingress_rules`, `ingress_cidr_blocks`, `egress_rules` | `security_group_id` |
| s3_alb_logs | app.terraform.io/hashi-demos-apj/s3-bucket/aws | ~> 6.0 | S3 bucket for ALB access logs with versioning, encryption, and log delivery policies | always | `bucket`, `environment`, `versioning`, `server_side_encryption_configuration`, `force_destroy`, `attach_elb_log_delivery_policy`, `attach_lb_log_delivery_policy` | `s3_bucket_name`, `s3_bucket_arn` |
| dynamodb | app.terraform.io/hashi-demos-apj/dynamodb-table/aws | ~> 5.2 | DynamoDB table with on-demand billing, PITR, and encryption | always | `name`, `hash_key`, `attributes`, `billing_mode`, `point_in_time_recovery_enabled`, `server_side_encryption_enabled`, `deletion_protection_enabled` | `dynamodb_table_arn`, `dynamodb_table_id` |
| sqs | app.terraform.io/hashi-demos-apj/sqs/aws | ~> 5.1 | SQS queue with DLQ, managed SSE, and configurable retention | always | `name`, `visibility_timeout_seconds`, `message_retention_seconds`, `create_dlq`, `redrive_policy` | `queue_arn`, `queue_url`, `queue_name`, `dead_letter_queue_arn` |
| sns_alerts | app.terraform.io/hashi-demos-apj/sns/aws | ~> 7.0 | SNS topic for operational alert notifications | always | `name`, `tags` | `topic_arn`, `topic_name` |
| alb_5xx_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | CloudWatch alarm for ALB 5xx error rate | always | `alarm_name`, `namespace`, `metric_name`, `threshold`, `evaluation_periods`, `period`, `statistic`, `comparison_operator`, `dimensions`, `alarm_actions`, `ok_actions` | `cloudwatch_metric_alarm_arn` |
| sqs_depth_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | CloudWatch alarm for SQS queue depth | always | `alarm_name`, `namespace`, `metric_name`, `threshold`, `evaluation_periods`, `period`, `statistic`, `comparison_operator`, `dimensions`, `alarm_actions` | `cloudwatch_metric_alarm_arn` |

### Glue Resources

| Resource Type | Logical Name | Purpose | Depends On |
|---------------|-------------|---------|------------|
| random_id | suffix | Generate unique hex suffix for globally unique S3 bucket naming | -- |

Data sources (not glue, but required for existing infrastructure lookup):

- `data.aws_vpc.selected` -- Look up existing VPC by tag Name or default VPC
- `data.aws_subnets.public` -- Discover public subnets in the selected VPC
- `data.aws_caller_identity.current` -- Account ID for Cloudability org-specific pricing

### Workspace Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| Organization | hashi-demos-apj | HCP Terraform organization |
| Project | sandbox | Workspace project assignment |
| Workspace | sandbox_consumer_web_stack | Target workspace |
| Execution Mode | Remote | HCP Terraform managed |
| Terraform Version | >= 1.14 | Pinned in workspace settings |
| Variable Sets | AWS Dynamic Credentials | `TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN` |
| VCS Connection | -- | Manual trigger or CLI-driven |
| Run Tasks | cloudability-governance (advisory, post_plan) | Cost governance via Cloudability Run Task |

---

## 3. Module Wiring

### Wiring Diagram

```
data.aws_vpc.selected
  ├─ .id ─────────────────→ module.alb (vpc_id)
  ├─ .id ─────────────────→ module.ec2_sg (vpc_id)
  └─ .cidr_block ─────────→ module.ec2_sg (ingress_cidr_blocks) [wrap: list]

data.aws_subnets.public
  ├─ .ids ────────────────→ module.alb (subnets)
  └─ .ids[0] ─────────────→ module.ec2_web (subnet_id) [element]

random_id.suffix
  └─ .hex ────────────────→ module.s3_alb_logs (bucket name via local)

module.s3_alb_logs
  └─ .s3_bucket_name ─────→ module.alb (access_logs.bucket)

module.ec2_sg
  └─ .security_group_id ──→ module.ec2_web (vpc_security_group_ids) [wrap: list]

module.ec2_web
  └─ .id ─────────────────→ module.alb (target_groups.web.target_id)

module.alb
  └─ .arn_suffix ─────────→ module.alb_5xx_alarm (dimensions.LoadBalancer)

module.sqs
  └─ .queue_name ─────────→ module.sqs_depth_alarm (dimensions.QueueName)

module.sns_alerts
  ├─ .topic_arn ──────────→ module.alb_5xx_alarm (alarm_actions) [wrap: list]
  ├─ .topic_arn ──────────→ module.alb_5xx_alarm (ok_actions) [wrap: list]
  ├─ .topic_arn ──────────→ module.sqs_depth_alarm (alarm_actions) [wrap: list]
  └─ .topic_arn ──────────→ module.sqs_depth_alarm (ok_actions) [wrap: list]
```

### Wiring Table

| Source Module | Output | Target Module | Input | Type | Transformation |
|--------------|--------|--------------|-------|------|----------------|
| data.aws_vpc.selected | id | alb | vpc_id | string | direct |
| data.aws_vpc.selected | id | ec2_sg | vpc_id | string | direct |
| data.aws_vpc.selected | cidr_block | ec2_sg | ingress_cidr_blocks | string -> list(string) | `[data.aws_vpc.selected.cidr_block]` |
| data.aws_subnets.public | ids | alb | subnets | list(string) | direct |
| data.aws_subnets.public | ids | ec2_web | subnet_id | list(string) -> string | `data.aws_subnets.public.ids[0]` |
| random_id.suffix | hex | s3_alb_logs | bucket | string | via `local.log_bucket_name` |
| s3_alb_logs | s3_bucket_name | alb | access_logs.bucket | string | direct (via object) |
| ec2_sg | security_group_id | ec2_web | vpc_security_group_ids | string -> list(string) | `[module.ec2_sg.security_group_id]` |
| ec2_web | id | alb | target_groups.web.target_id | string | direct |
| alb | arn_suffix | alb_5xx_alarm | dimensions.LoadBalancer | string | direct |
| sqs | queue_name | sqs_depth_alarm | dimensions.QueueName | string | direct |
| sns_alerts | topic_arn | alb_5xx_alarm | alarm_actions | string -> list(string) | `[module.sns_alerts.topic_arn]` |
| sns_alerts | topic_arn | alb_5xx_alarm | ok_actions | string -> list(string) | `[module.sns_alerts.topic_arn]` |
| sns_alerts | topic_arn | sqs_depth_alarm | alarm_actions | string -> list(string) | `[module.sns_alerts.topic_arn]` |
| sns_alerts | topic_arn | sqs_depth_alarm | ok_actions | string -> list(string) | `[module.sns_alerts.topic_arn]` |

### Provider Configuration

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Owner       = var.owner
      Application = var.application_name
    }
  }

  # Dynamic credentials injected by HCP Terraform -- no static keys
}
```

### Variables

| Variable | Type | Required | Default | Validation | Sensitive | Description |
|----------|------|----------|---------|------------|-----------|-------------|
| aws_region | string | No | "ap-southeast-2" | Must match `^[a-z]{2}-[a-z]+-[0-9]$` | No | AWS region for deployment |
| environment | string | No | "dev" | Must be one of: dev, staging, production | No | Environment name used for tagging and resource naming |
| project_name | string | Yes | -- | Must be 1-32 characters, lowercase alphanumeric and hyphens | No | Project name used for tagging and resource naming prefix |
| application_name | string | No | "web-stack" | Must be 1-32 characters, lowercase alphanumeric and hyphens | No | Application name for tagging |
| owner | string | Yes | -- | Must not be empty | No | Owner identifier for tagging (team or individual) |
| name_prefix | string | No | -- | Must be 1-24 characters, lowercase alphanumeric and hyphens; defaults to `"{project_name}-{environment}"` via locals if not set | No | Resource naming prefix; if not provided, derived from project_name and environment |
| vpc_name | string | No | "" | -- | No | VPC Name tag to look up; if empty, uses the default VPC |
| subnet_tier_tag | string | No | "Public" | -- | No | Tag value used to filter public subnets (key: Tier) |
| instance_type | string | No | "t3.small" | Must be a valid t3 or t3a family type | No | EC2 instance type for the web server |
| user_data | string | No | (httpd install script) | -- | No | User data script for the EC2 instance bootstrap |
| dynamodb_table_name | string | No | "app-data" | Must be 1-255 characters | No | Suffix for the DynamoDB table name |
| dynamodb_hash_key | string | No | "id" | Must not be empty | No | DynamoDB table partition key attribute name |
| sqs_message_retention_seconds | number | No | 345600 | Must be between 60 and 1209600 | No | SQS message retention period in seconds (default 4 days) |
| sqs_visibility_timeout_seconds | number | No | 30 | Must be between 0 and 43200 | No | SQS message visibility timeout in seconds |
| sqs_max_receive_count | number | No | 5 | Must be between 1 and 1000 | No | Maximum receive count before message is sent to DLQ |
| alarm_sns_email | string | No | "" | Must be a valid email format or empty | No | Email address to subscribe to the SNS alerts topic; no subscription created if empty |

### Outputs

| Output | Type | Source | Description |
|--------|------|--------|-------------|
| alb_dns_name | string | module.alb.dns_name | DNS name of the Application Load Balancer (primary application endpoint) |
| alb_arn | string | module.alb.arn | ARN of the Application Load Balancer |
| ec2_instance_id | string | module.ec2_web.id | Instance ID of the web server |
| ec2_public_ip | string | module.ec2_web.public_ip | Public IP address of the web server |
| s3_bucket_name | string | module.s3_alb_logs.s3_bucket_name | Name of the S3 bucket for ALB access logs |
| s3_bucket_arn | string | module.s3_alb_logs.s3_bucket_arn | ARN of the S3 bucket for ALB access logs |
| dynamodb_table_name | string | module.dynamodb.dynamodb_table_id | Name of the DynamoDB table |
| dynamodb_table_arn | string | module.dynamodb.dynamodb_table_arn | ARN of the DynamoDB table |
| sqs_queue_url | string | module.sqs.queue_url | URL of the SQS queue |
| sqs_queue_arn | string | module.sqs.queue_arn | ARN of the SQS queue |
| sqs_dlq_url | string | module.sqs.dead_letter_queue_url | URL of the SQS dead-letter queue |
| sns_topic_arn | string | module.sns_alerts.topic_arn | ARN of the SNS alerts topic |
| vpc_id | string | data.aws_vpc.selected.id | ID of the referenced VPC |

---

## 4. Security Controls

| Control | Enforcement | Module Config | Reference |
|---------|-------------|---------------|-----------|
| Encryption at rest (S3) | Module default: S3 bucket block public access enabled, SSE-S3 encryption via `server_side_encryption_configuration` input | `s3_alb_logs`: `server_side_encryption_configuration = { rule = { apply_server_side_encryption_by_default = { sse_algorithm = "AES256" } } }` | CIS AWS 2.1.1 -- S3 bucket server-side encryption enabled |
| Encryption at rest (DynamoDB) | Explicit enable via module input; module defaults to `false` | `dynamodb`: `server_side_encryption_enabled = true` (AWS-managed KMS key) | CIS AWS 3.x -- DynamoDB table encryption at rest |
| Encryption at rest (SQS) | Module default: `sqs_managed_sse_enabled = true` for both queue and DLQ | `sqs`: honour module defaults; `sqs_managed_sse_enabled = true`, `dlq_sqs_managed_sse_enabled = true` | CIS AWS 2.2 -- SQS queue encryption at rest |
| Encryption at rest (SNS) | Not enabled by default; SNS module requires explicit `kms_master_key_id` | `sns_alerts`: no KMS key set -- dev environment, no sensitive notification payloads. N/A justification: operational alerts contain metric names and thresholds only, no PII or secrets | AWS Well-Architected SEC08-BP01 |
| Encryption in transit | ALB module honours HTTP-only listener as specified; TLS is out of scope for this dev deployment | N/A -- no HTTPS listener configured. Traffic is HTTP within VPC only | `[SECURITY OVERRIDE]` Dev environment: HTTPS/TLS termination out of scope. Internal-only HTTP traffic between ALB and EC2. |
| Public access (S3) | Module secure defaults block all public access | `s3_alb_logs`: `block_public_acls = true`, `block_public_policy = true`, `ignore_public_acls = true`, `restrict_public_buckets = true` (module defaults -- DO NOT override) | CIS AWS 2.1.2 -- S3 bucket public access block |
| Public access (EC2) | EC2 in public subnet with public IP for dev access; HTTP ingress restricted to VPC CIDR | `ec2_sg`: `ingress_rules = ["http-80-tcp"]`, `ingress_cidr_blocks = [vpc_cidr]`. `ec2_web`: `associate_public_ip_address = true` | AWS Well-Architected SEC05-BP02 -- Control traffic at all layers |
| Public access (ALB) | ALB in public subnets, HTTP listener on port 80; ALB module creates its own security group | `alb`: `create_security_group = true` with HTTP/80 ingress rules configured via `security_group_ingress_rules` | AWS Well-Architected SEC05-BP03 |
| IAM least privilege | EC2 module defaults: no IAM instance profile created unless explicitly enabled; no wildcard permissions | `ec2_web`: `create_iam_instance_profile = false` (default) -- no IAM role attached; application does not require AWS API access in dev | CIS AWS 1.16 -- IAM policies attached only to groups or roles |
| IMDSv2 enforcement | Module secure default: `metadata_options.http_tokens = "required"` | `ec2_web`: module default enforced -- DO NOT override | CIS AWS 5.6 -- EC2 instance metadata service v2 |
| Deletion protection (ALB) | `[SECURITY OVERRIDE]` Dev environment: deletion protection disabled for easy teardown | `alb`: `enable_deletion_protection = false` (overrides module default of `true`) | AWS Well-Architected REL09-BP01 -- Deletion protection for production |
| Deletion protection (DynamoDB) | Explicit disable for dev; module default allows it | `dynamodb`: `deletion_protection_enabled = false` | AWS Well-Architected REL09-BP01 |
| Deletion protection (S3) | `[SECURITY OVERRIDE]` Dev environment: force destroy enabled for sandbox cleanup | `s3_alb_logs`: `force_destroy = true` (overrides module default of `false`) | AWS Well-Architected REL09-BP01 |
| Logging (ALB) | ALB access logs sent to S3 bucket with log delivery policies attached | `alb`: `access_logs = { bucket = module.s3_alb_logs.s3_bucket_name, enabled = true, prefix = "alb" }`. `s3_alb_logs`: `attach_elb_log_delivery_policy = true`, `attach_lb_log_delivery_policy = true` | CIS AWS 2.6 -- ELB logging enabled |
| Logging (ALB drop invalid headers) | Module secure default | `alb`: `drop_invalid_header_fields = true` (module default -- DO NOT override) | AWS Well-Architected SEC06-BP01 |
| Tagging | Provider `default_tags` propagate to all resources; module `tags` inputs for additional granularity | Provider: `default_tags` with `Environment`, `Project`, `ManagedBy`, `Owner`, `Application`. Each module receives `tags` for component-specific tags | CIS AWS 1.x -- Resource tagging for governance; AWS Well-Architected COST02-BP01 |

---

## 5. Implementation Checklist

- [x] **A: Scaffold** -- Create the file structure: `versions.tf` (terraform block with cloud block, required_version, required_providers), `providers.tf` (AWS provider with region and default_tags), `variables.tf` (all variables from the Variables table), `outputs.tf` (all outputs from the Outputs table), `locals.tf` (name_prefix, component names, common_tags, wiring computations), `data.tf` (aws_vpc, aws_subnets, aws_caller_identity data sources), `terraform.auto.tfvars.example` (example values)
- [ ] **B: Storage and Messaging modules** -- Add `random_id.suffix` glue resource and module calls in `main.tf` for `s3_alb_logs`, `dynamodb`, `sqs`, and `sns_alerts` with all required inputs wired. These modules have no upstream module dependencies and can be defined first. Files: `main.tf` (create)
- [ ] **C: Networking and Compute modules** -- Add module calls in `main.tf` for `ec2_sg` and `ec2_web` with VPC data source references wired. Wire security group output to EC2 instance input. Files: `main.tf` (modify)
- [ ] **D: Load Balancer and Monitoring modules** -- Add module calls in `main.tf` for `alb` (with target_groups referencing ec2_web.id, access_logs referencing s3_alb_logs, listeners), `alb_5xx_alarm`, and `sqs_depth_alarm`. Wire ALB arn_suffix and SQS queue_name to alarm dimensions, SNS topic_arn to alarm_actions. Files: `main.tf` (modify)
- [ ] **E: Polish** -- Generate `README.md` via terraform-docs, run `terraform fmt`, `terraform validate`, `tflint`, `trivy config .`. Verify all wiring connections match the wiring table. Create `.gitignore` for state and override files. Files: `README.md` (create), `.gitignore` (create)

---

## 6. Open Questions

No open questions. All requirements were clarified during Phase 1 and all module availability was confirmed during research.

---
