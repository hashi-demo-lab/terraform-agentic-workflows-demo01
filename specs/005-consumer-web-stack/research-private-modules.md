## Research: What private registry modules are available in `hashi-demos-apj` for a web application stack?

### Decision

All 8 requested module types exist in the `hashi-demos-apj` private registry with compatible interfaces and secure defaults. Use `s3-bucket` v6.0.0, `dynamodb-table` v5.2.0, `sqs` v5.1.0, `sns` v7.0.0, `cloudwatch` v5.7.2, `alb` v10.1.0, `ec2-instance` v6.1.4, and `security-group` v5.3.1. Additionally, supporting modules `vpc` v6.5.0, `acm` v6.1.1, and `autoscaling` v9.0.2 are available for a complete web application stack.

### Modules Identified

---

#### 1. S3 Bucket Module

- **Source**: `app.terraform.io/hashi-demos-apj/s3-bucket/aws` v6.0.0
- **Purpose**: S3 bucket with versioning, encryption, access logging, lifecycle rules, and public access block
- **AWS Provider**: `>= 6.5`
- **Key Inputs**:
  - `bucket` (optional, string) -- bucket name; if omitted, Terraform assigns a random unique name
  - `environment` (**required**, string) -- deployment environment, all consumers must specify
  - `versioning` (optional, map(string)) -- e.g. `{ enabled = true }`
  - `server_side_encryption_configuration` (optional, any) -- SSE config map
  - `logging` (optional, any) -- access bucket logging config
  - `attach_lb_log_delivery_policy` (optional, bool, default `false`) -- attach ALB/NLB log delivery policy
  - `attach_elb_log_delivery_policy` (optional, bool, default `false`) -- attach ELB log delivery policy
  - `attach_access_log_delivery_policy` (optional, bool, default `false`) -- S3 access log delivery policy
  - `attach_deny_insecure_transport_policy` (optional, bool, default `false`) -- deny non-SSL transport
  - `attach_require_latest_tls_policy` (optional, bool, default `false`) -- require latest TLS version
  - `lifecycle_rule` (optional, any) -- object lifecycle management rules
  - `force_destroy` (optional, bool, default `false`) -- allow deletion of non-empty bucket
  - `tags` (optional, map(string))
- **Key Outputs** (for cross-module wiring):
  - `s3_bucket_arn` (string) -- bucket ARN, used for IAM policies and CloudWatch alarms
  - `s3_bucket_name` (string) -- bucket name, used for ALB access_logs bucket reference
  - `s3_bucket_bucket_domain_name` (string) -- for CloudFront origins
  - `s3_bucket_bucket_regional_domain_name` (string) -- for CloudFront S3 origins (prevents redirects)
  - `s3_bucket_region` (string) -- bucket region
  - `s3_bucket_hosted_zone_id` (string) -- for Route53 alias records
- **Secure Defaults** (DO NOT override):
  - `block_public_acls = true`
  - `block_public_policy = true`
  - `ignore_public_acls = true`
  - `restrict_public_buckets = true`
  - `control_object_ownership = true`
  - `object_ownership = "BucketOwnerEnforced"` (ACLs disabled)
- **Wiring Notes**: For ALB access logs, set `attach_lb_log_delivery_policy = true` on the logs bucket. The `s3_bucket_name` output feeds into the ALB module's `access_logs.bucket` input.

---

#### 2. DynamoDB Table Module

- **Source**: `app.terraform.io/hashi-demos-apj/dynamodb-table/aws` v5.2.0
- **Purpose**: DynamoDB table with configurable billing mode, encryption, PITR, TTL, GSIs, LSIs, and autoscaling
- **AWS Provider**: `>= 6.13`
- **Key Inputs**:
  - `name` (optional, string) -- table name
  - `hash_key` (optional, string) -- partition key attribute name
  - `range_key` (optional, string) -- sort key attribute name
  - `attributes` (optional, list(map(string))) -- attribute definitions for keys
  - `billing_mode` (optional, string, default `"PAY_PER_REQUEST"`) -- already defaults to on-demand
  - `point_in_time_recovery_enabled` (optional, bool, default `false`) -- enable PITR
  - `server_side_encryption_enabled` (optional, bool, default `false`) -- enable encryption at rest
  - `server_side_encryption_kms_key_arn` (optional, string) -- custom KMS key ARN
  - `stream_enabled` (optional, bool, default `false`) -- enable DynamoDB Streams
  - `stream_view_type` (optional, string) -- KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES
  - `ttl_enabled` (optional, bool, default `false`)
  - `ttl_attribute_name` (optional, string)
  - `global_secondary_indexes` (optional, any)
  - `deletion_protection_enabled` (optional, bool)
  - `tags` (optional, map(string))
- **Key Outputs** (for cross-module wiring):
  - `dynamodb_table_arn` (string) -- for IAM policies, CloudWatch alarm dimensions
  - `dynamodb_table_id` (string) -- table name/ID
  - `dynamodb_table_stream_arn` (string) -- for Lambda triggers (only when stream_enabled=true)
  - `dynamodb_table_stream_label` (string) -- stream timestamp
- **Secure Defaults**: `billing_mode` defaults to `PAY_PER_REQUEST` (no over-provisioning risk). Encryption and PITR must be explicitly enabled -- the consumer design should set `server_side_encryption_enabled = true` and `point_in_time_recovery_enabled = true`.
- **Wiring Notes**: The `dynamodb_table_arn` feeds into IAM policies for EC2 instance profiles. The `dynamodb_table_id` can be used in CloudWatch alarm dimensions.

---

#### 3. SQS Module

- **Source**: `app.terraform.io/hashi-demos-apj/sqs/aws` v5.1.0
- **Purpose**: SQS queue with optional DLQ, redrive policy, queue policies, and encryption
- **AWS Provider**: `>= 6.0`
- **Key Inputs**:
  - `name` (optional, string) -- queue name
  - `sqs_managed_sse_enabled` (optional, bool, default `true`) -- SQS-managed SSE enabled by default
  - `kms_master_key_id` (optional, string) -- for CMK encryption instead of SQS-managed
  - `create_dlq` (optional, bool, default `false`) -- create dead letter queue
  - `redrive_policy` (optional, any) -- e.g. `{ maxReceiveCount = 5 }`
  - `dlq_sqs_managed_sse_enabled` (optional, bool, default `true`) -- DLQ SSE also defaults to true
  - `visibility_timeout_seconds` (optional, number)
  - `message_retention_seconds` (optional, number) -- 60 to 1209600 seconds
  - `receive_wait_time_seconds` (optional, number) -- for long polling
  - `fifo_queue` (optional, bool, default `false`)
  - `create_queue_policy` (optional, bool, default `false`)
  - `queue_policy_statements` (optional, map(object)) -- IAM policy statements for queue access
  - `tags` (optional, map(string))
- **Key Outputs** (for cross-module wiring):
  - `queue_arn` (string) -- for IAM policies, SNS subscriptions, CloudWatch alarms
  - `queue_url` (string) -- for application configuration
  - `queue_name` (string) -- for CloudWatch alarm dimensions
  - `dead_letter_queue_arn` (string) -- DLQ ARN
  - `dead_letter_queue_url` (string) -- DLQ URL
  - `dead_letter_queue_name` (string) -- DLQ name
  - `queue_arn_static` (string) -- use to avoid cycle errors (e.g., Step Functions)
- **Secure Defaults** (DO NOT override):
  - `sqs_managed_sse_enabled = true` -- encryption at rest enabled by default
  - `dlq_sqs_managed_sse_enabled = true` -- DLQ encryption also enabled by default
- **Wiring Notes**: The `queue_arn` feeds into SNS subscription endpoints and IAM policies. For SNS-to-SQS fan-out, use `create_queue_policy = true` with `queue_policy_statements` granting `sqs:SendMessage` from the SNS topic ARN.

---

#### 4. SNS Module

- **Source**: `app.terraform.io/hashi-demos-apj/sns/aws` v7.0.0
- **Purpose**: SNS topic with subscriptions, topic policies, and optional FIFO/encryption
- **AWS Provider**: `>= 6.9`
- **Key Inputs**:
  - `name` (optional, string) -- topic name (avoid AWS reserved words like "CloudFront")
  - `display_name` (optional, string) -- display name for SMS/email
  - `kms_master_key_id` (optional, string) -- KMS key for encryption at rest
  - `subscriptions` (optional, map(object)) -- map of subscriptions with `protocol` and `endpoint`
  - `topic_policy_statements` (optional, map(object)) -- IAM policy statements
  - `create_topic_policy` (optional, bool, default `true`)
  - `enable_default_topic_policy` (optional, bool, default `true`)
  - `fifo_topic` (optional, bool, default `false`)
  - `tags` (optional, map(string))
- **Key Outputs** (for cross-module wiring):
  - `topic_arn` (string) -- for CloudWatch alarm actions, SQS subscriptions, IAM policies
  - `topic_name` (string) -- topic name
  - `topic_id` (string) -- same as ARN
  - `subscriptions` (map) -- map of created subscriptions and their attributes
- **Secure Defaults**: Default topic policy is created and enabled. Encryption at rest is NOT enabled by default -- consumer must set `kms_master_key_id` or use `alias/aws/sns` for AWS-managed key.
- **Wiring Notes**: The `topic_arn` feeds into CloudWatch metric alarm `alarm_actions` and `ok_actions`. For SQS subscriptions, pass `queue_arn` as the subscription endpoint. Display name must not be a reserved word (e.g., use "CDN" instead of "CloudFront").

---

#### 5. CloudWatch Module

- **Source**: `app.terraform.io/hashi-demos-apj/cloudwatch/aws` v5.7.2
- **Purpose**: CloudWatch metric alarms, log groups, log metric filters, CIS alarms, composite alarms, metric streams, and anomaly detectors. This is a **submodule-based** module -- you use specific submodules for each capability.
- **AWS Provider**: varies by submodule
- **Key Submodules**:
  - `//modules/metric-alarm` -- individual metric alarms
  - `//modules/metric-alarms-by-multiple-dimensions` -- same alarm across multiple dimensions
  - `//modules/log-group` -- CloudWatch log groups
  - `//modules/log-metric-filter` -- log metric filters
  - `//modules/cis-alarms` -- CIS AWS Foundations benchmark alarms
  - `//modules/composite-alarm` -- composite alarms
  - `//modules/log-subscription-filter` -- log subscription filters
- **Key Inputs (metric-alarm submodule)**:
  - `alarm_name` (string) -- alarm name
  - `alarm_description` (string) -- alarm description
  - `comparison_operator` (string) -- GreaterThanOrEqualToThreshold, etc.
  - `evaluation_periods` (number) -- number of periods to evaluate
  - `threshold` (number) -- alarm threshold value
  - `period` (number) -- evaluation period in seconds
  - `namespace` (string) -- CloudWatch namespace (e.g., "AWS/SQS", "AWS/DynamoDB")
  - `metric_name` (string) -- metric name
  - `statistic` (string) -- Maximum, Average, Sum, etc.
  - `alarm_actions` (list(string)) -- SNS topic ARNs
  - `ok_actions` (list(string)) -- SNS topic ARNs for OK state
  - `dimensions` (map(string)) -- metric dimensions (e.g., QueueName, TableName)
  - `tags` (map(string))
- **Key Outputs (metric-alarm submodule)**:
  - `cloudwatch_metric_alarm_arn` (string)
  - `cloudwatch_metric_alarm_id` (string)
- **Wiring Notes**: Since this is a submodule-based module, each alarm is a separate module call using the `//modules/metric-alarm` path. The `alarm_actions` input takes the SNS module's `topic_arn` output. Dimensions reference resource names/ARNs from other modules (e.g., SQS `queue_name`, DynamoDB `dynamodb_table_id`).

---

#### 6. ALB Module

- **Source**: `app.terraform.io/hashi-demos-apj/alb/aws` v10.1.0
- **Purpose**: Application/Network Load Balancer with listeners, target groups, security groups, Route53 records, and WAF integration
- **AWS Provider**: `>= 6.19`
- **Key Inputs**:
  - `name` (optional, string) -- LB name (max 32 chars, alphanumeric + hyphens)
  - `load_balancer_type` (optional, string, default `"application"`)
  - `vpc_id` (optional, string) -- VPC ID for security group creation
  - `subnets` (optional, list(string)) -- subnet IDs to attach
  - `internal` (optional, bool, default `false`)
  - `security_groups` (optional, list(string)) -- external security group IDs
  - `create_security_group` (optional, bool, default `true`) -- creates its own SG
  - `security_group_ingress_rules` (optional, map(object)) -- ingress rules for created SG
  - `security_group_egress_rules` (optional, map(object)) -- egress rules for created SG
  - `listeners` (optional, map(object)) -- listener configurations with protocol, port, actions, rules
  - `target_groups` (optional, map(object)) -- target group configs with health checks
  - `access_logs` (optional, object) -- `{ bucket = "...", enabled = true, prefix = "..." }`
  - `tags` (optional, map(string))
- **Key Outputs** (for cross-module wiring):
  - `arn` (string) -- LB ARN
  - `dns_name` (string) -- LB DNS name, for Route53 alias records or application config
  - `zone_id` (string) -- LB Route53 zone ID, for alias records
  - `arn_suffix` (string) -- for CloudWatch metric dimensions
  - `security_group_id` (string) -- created SG ID, for EC2/ASG security group references
  - `security_group_arn` (string)
  - `target_groups` (map) -- map of target groups with their attributes
  - `listeners` (map) -- map of listeners with their attributes
- **Secure Defaults** (DO NOT override):
  - `enable_deletion_protection = true` -- prevents accidental deletion
  - `drop_invalid_header_fields = true` -- security best practice for ALB
  - `enable_cross_zone_load_balancing = true`
- **Wiring Notes**: VPC module's `vpc_id` output feeds into `vpc_id`. VPC module's `public_subnets` output feeds into `subnets`. The `target_groups` map accepts `target_id` for individual instances or can be used with ASG via `traffic_source_attachments` in the autoscaling module. The `access_logs.bucket` takes the S3 bucket name from the logs bucket module.

---

#### 7. EC2 Instance Module

- **Source**: `app.terraform.io/hashi-demos-apj/ec2-instance/aws` v6.1.4
- **Purpose**: Individual EC2 instance with optional IAM instance profile, security group, EBS volumes, and EIP
- **AWS Provider**: `>= 6.0`
- **Key Inputs**:
  - `name` (optional, string) -- instance name tag
  - `ami` (optional, string) -- AMI ID; if omitted, uses `ami_ssm_parameter`
  - `ami_ssm_parameter` (optional, string, default `"/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"`)
  - `instance_type` (optional, string, default `"t3.micro"`)
  - `subnet_id` (optional, string) -- VPC subnet to launch in
  - `vpc_security_group_ids` (optional, list(string)) -- security group IDs
  - `key_name` (optional, string) -- SSH key pair name
  - `monitoring` (optional, bool) -- detailed monitoring
  - `user_data` (optional, string) -- user data script
  - `user_data_base64` (optional, string) -- base64-encoded user data
  - `create_iam_instance_profile` (optional, bool, default `false`)
  - `iam_role_policies` (optional, map(string)) -- IAM policies to attach
  - `create_security_group` (optional, bool, default `true`)
  - `security_group_vpc_id` (optional, string) -- VPC for created SG
  - `security_group_ingress_rules` (optional, map(object))
  - `security_group_egress_rules` (optional, map(object))
  - `root_block_device` (optional, object) -- root volume config
  - `ebs_volumes` (optional, map(object)) -- additional EBS volumes
  - `tags` (optional, map(string))
- **Key Outputs** (for cross-module wiring):
  - `id` (string) -- instance ID, for ALB target group attachment
  - `arn` (string) -- instance ARN
  - `private_ip` (string) -- private IP address
  - `public_ip` (string) -- public IP (if applicable)
  - `private_dns` (string) -- private DNS name
  - `security_group_id` (string) -- created SG ID
  - `iam_role_arn` (string) -- IAM role ARN
  - `iam_instance_profile_arn` (string) -- instance profile ARN
  - `availability_zone` (string)
- **Secure Defaults** (DO NOT override):
  - `metadata_options.http_tokens = "required"` -- IMDSv2 enforced
  - `metadata_options.http_put_response_hop_limit = 1` -- single hop limit
  - `metadata_options.http_endpoint = "enabled"`
- **Wiring Notes**: VPC module's `private_subnets` output provides `subnet_id`. Security group module's `security_group_id` or ALB module's `security_group_id` can feed into `vpc_security_group_ids`. The `id` output feeds into ALB target group's `target_id`. For ASG-based deployments, prefer the `autoscaling` module instead.

---

#### 8. Security Group Module

- **Source**: `app.terraform.io/hashi-demos-apj/security-group/aws` v5.3.1
- **Purpose**: Security group with predefined rules, custom rules, CIDR blocks, source security groups, prefix lists, and self-references
- **AWS Provider**: `>= 3.29`
- **Key Inputs**:
  - `name` (optional, string) -- security group name
  - `vpc_id` (optional, string) -- VPC to create the SG in
  - `description` (optional, string, default `"Security Group managed by Terraform"`)
  - `ingress_rules` (optional, list(string)) -- predefined rule names (e.g., `["http-80-tcp", "https-443-tcp"]`)
  - `ingress_cidr_blocks` (optional, list(string)) -- CIDR blocks for ingress rules
  - `ingress_with_cidr_blocks` (optional, list(map(string))) -- custom ingress rules with CIDR
  - `ingress_with_source_security_group_id` (optional, list(map(string))) -- ingress from other SGs
  - `egress_rules` (optional, list(string)) -- predefined egress rule names
  - `egress_cidr_blocks` (optional, list(string), default `["0.0.0.0/0"]`)
  - `tags` (optional, map(string))
- **Key Outputs** (for cross-module wiring):
  - `security_group_id` (string) -- SG ID, feeds into EC2, ALB, ASG modules
  - `security_group_arn` (string) -- SG ARN
  - `security_group_name` (string)
  - `security_group_vpc_id` (string)
  - `security_group_owner_id` (string)
- **Predefined Rules Available** (relevant for web stack):
  - `http-80-tcp` -- port 80 TCP
  - `https-443-tcp` -- port 443 TCP
  - `ssh-tcp` -- port 22 TCP
  - `all-all` -- all protocols
- **Wiring Notes**: VPC module's `vpc_id` output feeds into `vpc_id`. The `security_group_id` output feeds into EC2 module's `vpc_security_group_ids`, ALB module's `security_groups`, and ASG module's `security_groups`. Note that the ALB module can create its own security group, so you may use either this standalone module or the ALB's built-in SG creation. For inter-module SG references (ALB -> EC2), use `ingress_with_source_security_group_id`.

---

### Supporting Modules (Available in Private Registry)

#### VPC Module
- **Source**: `app.terraform.io/hashi-demos-apj/vpc/aws` v6.5.0
- **Purpose**: VPC with public/private/database/intra subnets, NAT gateways, flow logs
- **Key Outputs**: `vpc_id`, `private_subnets`, `public_subnets`, `database_subnets`, `vpc_cidr_block`, `private_subnets_cidr_blocks`, `public_subnets_cidr_blocks`
- **Wiring**: Provides `vpc_id` and subnet IDs consumed by ALB, EC2, ASG, and security group modules

#### ACM Module
- **Source**: `app.terraform.io/hashi-demos-apj/acm/aws` v6.1.1
- **Purpose**: TLS certificate management with DNS validation via Route53
- **Key Outputs**: `acm_certificate_arn` -- feeds into ALB listener's `certificate_arn`

#### Autoscaling Module
- **Source**: `app.terraform.io/hashi-demos-apj/autoscaling/aws` v9.0.2
- **Purpose**: Auto Scaling Group with launch template, scaling policies, instance refresh
- **Key Inputs**: `vpc_zone_identifier` (subnet IDs), `security_groups`, `image_id`, `instance_type`, `traffic_source_attachments`
- **Key Outputs**: `autoscaling_group_arn`, `autoscaling_group_name`, `launch_template_id`
- **Secure Defaults**: IMDSv2 required by default (`metadata_options.http_tokens = "required"`)

---

### Glue Resources Needed

- **None strictly required** -- all 8 requested components have private registry modules with compatible interfaces
- **Optional**: `random_string` or `random_id` for unique naming suffixes (e.g., S3 bucket names must be globally unique)
- **Optional**: `aws_caller_identity` data source if IAM policies need the account ID

### Cross-Module Wiring Summary

| From Module | Output | To Module | Input |
|-------------|--------|-----------|-------|
| VPC | `vpc_id` | ALB, Security Group, EC2 | `vpc_id` |
| VPC | `public_subnets` | ALB | `subnets` |
| VPC | `private_subnets` | EC2, ASG | `subnet_id` / `vpc_zone_identifier` |
| S3 (logs bucket) | `s3_bucket_name` | ALB | `access_logs.bucket` |
| ALB | `security_group_id` | Security Group (EC2) | `ingress_with_source_security_group_id` |
| ALB | `target_groups` | ASG | `traffic_source_attachments` |
| ALB | `arn_suffix` | CloudWatch metric-alarm | `dimensions` |
| Security Group | `security_group_id` | EC2, ASG | `vpc_security_group_ids` / `security_groups` |
| EC2 | `id` | ALB target group | `target_id` |
| SNS | `topic_arn` | CloudWatch metric-alarm | `alarm_actions`, `ok_actions` |
| SNS | `topic_arn` | SQS (subscription) | `subscriptions.sqs.endpoint` |
| SQS | `queue_arn` | SNS topic policy, IAM | policy references |
| SQS | `queue_name` | CloudWatch metric-alarm | `dimensions.QueueName` |
| DynamoDB | `dynamodb_table_arn` | IAM policies | resource ARN |
| DynamoDB | `dynamodb_table_id` | CloudWatch metric-alarm | `dimensions.TableName` |
| ACM | `acm_certificate_arn` | ALB HTTPS listener | `certificate_arn` |

### Provider Version Compatibility

All modules require AWS provider v6.x. The highest minimum version across all modules is:

| Module | Min AWS Provider |
|--------|-----------------|
| ALB | >= 6.19 |
| DynamoDB | >= 6.13 |
| Autoscaling | >= 6.12 |
| SNS | >= 6.9 |
| S3 Bucket | >= 6.5 |
| VPC | >= 6.5 (estimated) |
| ACM | >= 6.4 |
| EC2 Instance | >= 6.0 |
| SQS | >= 6.0 |
| Security Group | >= 3.29 |

**Recommendation**: Pin `aws` provider to `~> 6.19` to satisfy all module constraints.

### Rationale

All 8 requested module types exist in the `hashi-demos-apj` private registry. These modules are forks of the well-known `terraform-aws-modules` community modules (maintained by Anton Babenko), customized for the organization. The S3 bucket module adds a required `environment` input. All modules use compatible output naming conventions and types, enabling straightforward cross-module wiring without type transformations. The ALB module (v10.1.0) has the highest AWS provider version requirement (>= 6.19), which sets the floor for the entire stack.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Public registry `terraform-aws-modules/*` | Organization policy requires private registry modules; the private modules are org-customized forks of these same modules |
| Raw `aws_*` resources | Consumer constitution prohibits raw resources; compose from private modules |
| Separate security group module for ALB | ALB module v10.1.0 has built-in security group creation (`create_security_group = true`); use built-in for ALB, standalone module for EC2/backend |
| CloudWatch module root (no submodule) | CloudWatch module is submodule-based -- root module has no inputs/outputs; must use `//modules/metric-alarm` path |
| Single EC2 instance for production | For production, prefer `autoscaling` module (v9.0.2) for HA; `ec2-instance` is suitable for dev/single-instance scenarios |

### Sources

- Private registry: `app.terraform.io/hashi-demos-apj` -- all 30 modules enumerated via `search_private_modules`
- Module details: `get_private_module_details` for each of the 11 modules documented above
- VCS source: `github.com/hashi-demo-lab/terraform-aws-*` repositories (forks of terraform-aws-modules)
