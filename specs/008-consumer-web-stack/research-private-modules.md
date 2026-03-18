## Research: What private registry modules are available in hashi-demos-apj for building a web application stack?

### Decision

The `hashi-demos-apj` private registry contains all modules needed for a complete web application stack: ALB, EC2, S3, DynamoDB, SQS, SNS, CloudWatch, Security Group, and VPC. Supporting modules for ACM, Route53, Autoscaling, KMS, and IAM are also available. No public registry modules are needed.

### Modules Identified

#### 1. ALB / Load Balancer

- **Module**: `app.terraform.io/hashi-demos-apj/alb/aws` v10.1.0
  - **Purpose**: Application/Network Load Balancer with target groups, listeners, security groups, and Route53 records
  - **Provider**: `hashicorp/aws >= 6.19`
  - **Required Inputs**: None strictly required; all have defaults
  - **Key Inputs**:
    - `name` (string) -- LB name, max 32 chars
    - `vpc_id` (string) -- VPC ID for security group creation
    - `subnets` (list(string)) -- subnet IDs to attach to LB
    - `internal` (bool, default: null/false) -- whether LB is internal
    - `load_balancer_type` (string, default: "application") -- "application", "gateway", or "network"
    - `listeners` (map(object)) -- map of listener configs (port, protocol, certificate_arn, forward, redirect, rules)
    - `target_groups` (map(object)) -- map of target group configs (protocol, port, target_type, target_id, health_check, vpc_id)
    - `security_group_ingress_rules` (map(object)) -- ingress rules for auto-created SG
    - `security_group_egress_rules` (map(object)) -- egress rules for auto-created SG
    - `create_security_group` (bool, default: true) -- whether to create a security group
    - `security_groups` (list(string)) -- external SG IDs to assign
    - `access_logs` (object) -- bucket, enabled, prefix for access logging
    - `tags` (map(string))
  - **Key Outputs**:
    - `arn` (string) -- ARN of the load balancer
    - `arn_suffix` (string) -- ARN suffix for CloudWatch
    - `dns_name` (string) -- DNS name of LB
    - `zone_id` (string) -- Route53 zone ID for alias records
    - `id` (string) -- same as ARN
    - `security_group_id` (string) -- ID of auto-created SG
    - `security_group_arn` (string) -- ARN of auto-created SG
    - `target_groups` (map) -- map of created target groups and their attributes
    - `listeners` (map) -- map of created listeners and their attributes
    - `listener_rules` (map) -- map of created listener rules
    - `route53_records` (map) -- Route53 records created
  - **Secure Defaults**:
    - `enable_deletion_protection = true`
    - `drop_invalid_header_fields = true`
    - `enable_cross_zone_load_balancing = true`
  - **Wiring Notes**: `arn_suffix` feeds into CloudWatch metric alarms; `dns_name`+`zone_id` feed into Route53 alias records; `security_group_id` can be referenced by EC2 egress rules; `target_groups` map provides ARNs for autoscaling group attachment

#### 2. EC2 Instance / Compute

- **Module**: `app.terraform.io/hashi-demos-apj/ec2-instance/aws` v6.1.4
  - **Purpose**: Single EC2 instance with optional IAM role, security group, EIP, and EBS volumes
  - **Provider**: `hashicorp/aws >= 6.0`
  - **Required Inputs**: None strictly required (AMI defaults to AL2023 via SSM parameter)
  - **Key Inputs**:
    - `name` (string) -- instance name tag
    - `ami` (string, default: null) -- AMI ID; if null, uses `ami_ssm_parameter`
    - `ami_ssm_parameter` (string, default: "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64")
    - `instance_type` (string, default: "t3.micro")
    - `subnet_id` (string) -- VPC subnet to launch in
    - `key_name` (string) -- SSH key pair name
    - `vpc_security_group_ids` (list(string)) -- security group IDs
    - `user_data` (string) -- startup script
    - `user_data_base64` (string) -- base64 encoded user data
    - `create_security_group` (bool, default: true)
    - `security_group_vpc_id` (string) -- VPC ID for auto-created SG
    - `security_group_ingress_rules` (map(object)) -- ingress rules
    - `security_group_egress_rules` (map(object)) -- egress rules (defaults to allow all IPv4/IPv6)
    - `create_iam_instance_profile` (bool, default: false) -- whether to create IAM profile
    - `iam_role_policies` (map(string)) -- IAM policies to attach
    - `monitoring` (bool) -- detailed monitoring
    - `root_block_device` (object) -- root volume config
    - `tags` (map(string))
    - `associate_public_ip_address` (bool)
    - `create_eip` (bool, default: false)
  - **Key Outputs**:
    - `id` (string) -- instance ID
    - `arn` (string) -- instance ARN
    - `private_ip` (string) -- private IP address
    - `public_ip` (string) -- public IP (if applicable)
    - `private_dns` (string) -- private DNS name
    - `public_dns` (string) -- public DNS name
    - `security_group_id` (string) -- ID of auto-created SG
    - `security_group_arn` (string) -- ARN of auto-created SG
    - `iam_role_arn` (string) -- ARN of IAM role
    - `iam_role_name` (string) -- name of IAM role
    - `iam_instance_profile_arn` (string) -- instance profile ARN
    - `instance_state` (string) -- running state
    - `availability_zone` (string) -- AZ of the instance
  - **Secure Defaults**:
    - `metadata_options`: IMDSv2 required (`http_tokens = "required"`, `http_put_response_hop_limit = 1`)
    - Security group egress defaults to allow all (configurable)
  - **Wiring Notes**: `id` feeds into ALB target group `target_id`; `security_group_id` can be used by ALB egress rules; `private_ip` can be used for internal DNS. For multi-instance, use `for_each` on the module block.

#### 3. S3 Bucket / Storage

- **Module**: `app.terraform.io/hashi-demos-apj/s3-bucket/aws` v6.0.0
  - **Purpose**: S3 bucket with versioning, encryption, lifecycle, CORS, access logging, and policies
  - **Provider**: `hashicorp/aws >= 6.5`
  - **Required Inputs**:
    - `environment` (string) -- **REQUIRED** -- deployment environment name
  - **Key Inputs**:
    - `bucket` (string) -- bucket name (random if omitted)
    - `bucket_prefix` (string) -- bucket name prefix
    - `versioning` (map(string)) -- e.g. `{ enabled = true }`
    - `server_side_encryption_configuration` (any) -- SSE config
    - `lifecycle_rule` (any) -- lifecycle management rules
    - `cors_rule` (any) -- CORS rules
    - `logging` (any) -- access logging config
    - `website` (any) -- static website hosting config
    - `attach_deny_insecure_transport_policy` (bool, default: false) -- deny non-SSL transport
    - `attach_lb_log_delivery_policy` (bool, default: false) -- ALB/NLB log delivery policy
    - `attach_elb_log_delivery_policy` (bool, default: false) -- ELB log delivery policy
    - `force_destroy` (bool, default: false)
    - `tags` (map(string))
  - **Key Outputs**:
    - `s3_bucket_id` -- NOT LISTED, use `s3_bucket_name` instead
    - `s3_bucket_arn` (string) -- bucket ARN
    - `s3_bucket_name` (string) -- bucket name
    - `s3_bucket_bucket_domain_name` (string) -- bucket domain name
    - `s3_bucket_bucket_regional_domain_name` (string) -- regional domain name
    - `s3_bucket_hosted_zone_id` (string) -- Route53 hosted zone ID
    - `s3_bucket_region` (string) -- bucket region
    - `s3_bucket_website_endpoint` (string) -- website endpoint
    - `s3_bucket_website_domain` (string) -- website domain
    - `s3_bucket_tags` (map) -- bucket tags
  - **Secure Defaults**:
    - `block_public_acls = true`
    - `block_public_policy = true`
    - `ignore_public_acls = true`
    - `restrict_public_buckets = true`
    - `control_object_ownership = true`
    - `object_ownership = "BucketOwnerEnforced"` (ACLs disabled)
  - **Wiring Notes**: `s3_bucket_arn` + `s3_bucket_name` feed into IAM policies for EC2 access; `s3_bucket_name` feeds into ALB `access_logs` bucket; `s3_bucket_bucket_regional_domain_name` + `s3_bucket_hosted_zone_id` feed into CloudFront/Route53 alias records

#### 4. DynamoDB Table

- **Module**: `app.terraform.io/hashi-demos-apj/dynamodb-table/aws` v5.2.0
  - **Purpose**: DynamoDB table with optional autoscaling, GSIs, LSIs, streams, and PITR
  - **Provider**: `hashicorp/aws >= 6.13`
  - **Required Inputs**: None strictly required (all have defaults)
  - **Key Inputs**:
    - `name` (string) -- table name
    - `hash_key` (string) -- partition key attribute name
    - `range_key` (string) -- sort key attribute name
    - `attributes` (list(map(string))) -- attribute definitions `[{name, type}]`
    - `billing_mode` (string, default: "PAY_PER_REQUEST") -- PAY_PER_REQUEST or PROVISIONED
    - `read_capacity` (number) -- for PROVISIONED mode
    - `write_capacity` (number) -- for PROVISIONED mode
    - `global_secondary_indexes` (any) -- GSI definitions
    - `local_secondary_indexes` (any) -- LSI definitions
    - `ttl_enabled` (bool, default: false)
    - `ttl_attribute_name` (string)
    - `stream_enabled` (bool, default: false)
    - `stream_view_type` (string) -- KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES
    - `point_in_time_recovery_enabled` (bool, default: false)
    - `server_side_encryption_enabled` (bool, default: false) -- NOTE: defaults to OFF
    - `server_side_encryption_kms_key_arn` (string)
    - `deletion_protection_enabled` (bool)
    - `autoscaling_enabled` (bool, default: false)
    - `autoscaling_read` (map(string)) -- read autoscaling settings
    - `autoscaling_write` (map(string)) -- write autoscaling settings
    - `tags` (map(string))
  - **Key Outputs**:
    - `dynamodb_table_arn` (string) -- table ARN
    - `dynamodb_table_id` (string) -- table name/ID
    - `dynamodb_table_stream_arn` (string) -- stream ARN (when stream enabled)
    - `dynamodb_table_stream_label` (string) -- stream timestamp label
  - **Secure Defaults**:
    - `billing_mode = "PAY_PER_REQUEST"` (cost-safe default)
    - WARNING: `server_side_encryption_enabled` defaults to `false` -- consumer should enable it
  - **Wiring Notes**: `dynamodb_table_arn` feeds into IAM policies for EC2/Lambda access; `dynamodb_table_id` is the table name for application configuration; `dynamodb_table_stream_arn` feeds into Lambda event source mappings

#### 5. SQS / Messaging

- **Module**: `app.terraform.io/hashi-demos-apj/sqs/aws` v5.1.0
  - **Purpose**: SQS queue with optional dead letter queue, queue policies, and redrive policies
  - **Provider**: `hashicorp/aws >= 6.0`
  - **Required Inputs**: None strictly required
  - **Key Inputs**:
    - `name` (string) -- queue name
    - `fifo_queue` (bool, default: false) -- FIFO queue
    - `visibility_timeout_seconds` (number) -- message visibility timeout
    - `message_retention_seconds` (number) -- retention period (60-1209600)
    - `max_message_size` (number) -- max message size
    - `delay_seconds` (number) -- delivery delay
    - `receive_wait_time_seconds` (number) -- long polling wait time
    - `sqs_managed_sse_enabled` (bool, default: true) -- SQS-owned SSE
    - `kms_master_key_id` (string) -- custom KMS key
    - `create_dlq` (bool, default: false) -- create dead letter queue
    - `redrive_policy` (any) -- DLQ redrive config `{ maxReceiveCount = N }`
    - `create_queue_policy` (bool, default: false)
    - `queue_policy_statements` (map(object)) -- IAM policy statements
    - `tags` (map(string))
  - **Key Outputs**:
    - `queue_arn` (string) -- queue ARN
    - `queue_id` (string) -- queue URL
    - `queue_url` (string) -- same as queue_id
    - `queue_name` (string) -- queue name
    - `queue_arn_static` (string) -- ARN that avoids cycle errors
    - `dead_letter_queue_arn` (string) -- DLQ ARN
    - `dead_letter_queue_id` (string) -- DLQ URL
    - `dead_letter_queue_url` (string) -- same as DLQ id
    - `dead_letter_queue_name` (string) -- DLQ name
  - **Secure Defaults**:
    - `sqs_managed_sse_enabled = true` (encryption at rest)
    - DLQ SSE also enabled by default (`dlq_sqs_managed_sse_enabled = true`)
  - **Wiring Notes**: `queue_arn` feeds into SNS subscription endpoints and IAM policies; `queue_url` is used by application config; `queue_arn` feeds into SNS topic policy for publish permission

#### 6. SNS / Notifications

- **Module**: `app.terraform.io/hashi-demos-apj/sns/aws` v7.0.0
  - **Purpose**: SNS topic with subscriptions, topic policies, and data protection
  - **Provider**: `hashicorp/aws >= 6.9`
  - **Required Inputs**: None strictly required
  - **Key Inputs**:
    - `name` (string) -- topic name
    - `display_name` (string) -- display name
    - `fifo_topic` (bool, default: false)
    - `kms_master_key_id` (string) -- KMS key for encryption
    - `subscriptions` (map(object)) -- map of subscription definitions `{ protocol, endpoint, ... }`
    - `topic_policy_statements` (map(object)) -- IAM policy statements for topic policy
    - `create_topic_policy` (bool, default: true)
    - `enable_default_topic_policy` (bool, default: true)
    - `tags` (map(string))
  - **Key Outputs**:
    - `topic_arn` (string) -- topic ARN
    - `topic_id` (string) -- same as ARN
    - `topic_name` (string) -- topic name
    - `topic_owner` (string) -- AWS account ID of owner
    - `subscriptions` (map) -- map of created subscriptions
  - **Secure Defaults**:
    - Default topic policy is enabled
  - **Wiring Notes**: `topic_arn` feeds into SQS subscription endpoints, CloudWatch alarm actions, and IAM policies; SNS subscriptions to SQS require cross-service queue policy on SQS side

#### 7. CloudWatch / Monitoring

- **Module**: `app.terraform.io/hashi-demos-apj/cloudwatch/aws` v5.7.2
  - **Purpose**: CloudWatch resources via submodules -- log groups, metric filters, metric alarms, CIS alarms, composite alarms, log streams, query definitions, metric streams
  - **Provider**: aws (version not shown in top-level -- submodule-based)
  - **IMPORTANT**: This is a **submodule-based** module. You invoke submodules like:
    - `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/log-group` -- Log groups
    - `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm` -- Metric alarms
    - `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/log-metric-filter` -- Log metric filters
    - `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/log-stream` -- Log streams
    - `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarms-by-multiple-dimensions` -- Alarms by multiple dimensions
    - `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/cis-alarms` -- CIS Foundation alarms
    - `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/composite-alarm` -- Composite alarms
  - **Key Inputs for `metric-alarm` submodule** (from README examples):
    - `alarm_name` (string) -- alarm name
    - `alarm_description` (string) -- description
    - `comparison_operator` (string) -- e.g. "GreaterThanOrEqualToThreshold"
    - `evaluation_periods` (number) -- number of periods
    - `threshold` (number) -- threshold value
    - `period` (number) -- seconds per period
    - `unit` (string) -- e.g. "Count"
    - `namespace` (string) -- e.g. "AWS/ApplicationELB"
    - `metric_name` (string) -- metric name
    - `statistic` (string) -- e.g. "Maximum", "Average"
    - `alarm_actions` (list(string)) -- SNS topic ARNs
  - **Key Inputs for `log-group` submodule**:
    - `name` (string) -- log group name
    - `retention_in_days` (number) -- log retention
  - **Wiring Notes**: `alarm_actions` takes SNS `topic_arn` values; metric alarms for ALB use `AWS/ApplicationELB` namespace with dimension `LoadBalancer` = ALB `arn_suffix`

#### 8. Security Group

- **Module**: `app.terraform.io/hashi-demos-apj/security-group/aws` v5.3.1
  - **Purpose**: EC2 security group with extensive predefined rules, custom rules, and computed rules
  - **Provider**: `hashicorp/aws >= 3.29`
  - **Required Inputs**: None strictly required
  - **Key Inputs**:
    - `name` (string) -- security group name
    - `description` (string, default: "Security Group managed by Terraform")
    - `vpc_id` (string) -- VPC ID
    - `ingress_rules` (list(string)) -- predefined rule names (e.g. "http-80-tcp", "https-443-tcp", "ssh-tcp")
    - `ingress_cidr_blocks` (list(string)) -- CIDR blocks for ingress rules
    - `ingress_with_cidr_blocks` (list(map(string))) -- custom ingress rules with CIDRs
    - `ingress_with_source_security_group_id` (list(map(string))) -- ingress from other SGs
    - `egress_rules` (list(string)) -- predefined egress rule names
    - `egress_cidr_blocks` (list(string), default: ["0.0.0.0/0"])
    - `use_name_prefix` (bool, default: true) -- use name as prefix for unique naming
    - `tags` (map(string))
  - **Key Outputs**:
    - `security_group_id` (string) -- the SG ID
    - `security_group_arn` (string) -- the SG ARN
    - `security_group_name` (string) -- the SG name
    - `security_group_vpc_id` (string) -- VPC ID
    - `security_group_owner_id` (string) -- owner account ID
    - `security_group_description` (string) -- SG description
  - **Built-in Predefined Rules** (useful for web stack):
    - `http-80-tcp`, `http-8080-tcp`, `https-443-tcp`, `https-8443-tcp`, `ssh-tcp`
    - `postgresql-tcp`, `mysql-tcp`, `redis-tcp`, `memcached-tcp`
    - `all-all`, `all-tcp`, `all-udp`
  - **Wiring Notes**: `security_group_id` feeds into EC2 `vpc_security_group_ids`, ALB `security_groups`, and other module SG references. NOTE: ALB module can also create its own SG via `create_security_group = true` -- consider whether to use ALB's built-in SG or this standalone module.

#### 9. VPC

- **Module**: `app.terraform.io/hashi-demos-apj/vpc/aws` v6.5.0
  - **Purpose**: Full VPC with public/private/database subnets, NAT gateways, VPN gateway, flow logs, and VPC endpoints
  - **Provider**: `hashicorp/aws >= 5.53`
  - **Required Inputs**: None strictly required
  - **Key Inputs**:
    - `name` (string) -- VPC name
    - `cidr` (string, default: "10.0.0.0/16") -- VPC CIDR block
    - `azs` (list(string)) -- availability zones
    - `private_subnets` (list(string)) -- private subnet CIDRs
    - `public_subnets` (list(string)) -- public subnet CIDRs
    - `database_subnets` (list(string)) -- database subnet CIDRs
    - `enable_nat_gateway` (bool, default: false) -- create NAT gateways
    - `single_nat_gateway` (bool, default: false) -- use one NAT for all AZs
    - `one_nat_gateway_per_az` (bool, default: false) -- one NAT per AZ
    - `enable_dns_hostnames` (bool, default: true)
    - `enable_dns_support` (bool, default: true)
    - `enable_flow_log` (bool) -- VPC flow logs
    - `tags` (map(string))
  - **Key Outputs**:
    - `vpc_id` (string) -- VPC ID
    - `vpc_arn` (string) -- VPC ARN
    - `vpc_cidr_block` (string) -- VPC CIDR
    - `private_subnets` (list(string)) -- private subnet IDs
    - `public_subnets` (list(string)) -- public subnet IDs
    - `database_subnets` (list(string)) -- database subnet IDs
    - `private_subnet_arns` (list(string))
    - `public_subnet_arns` (list(string))
    - `natgw_ids` (list(string)) -- NAT gateway IDs
    - `igw_id` (string) -- Internet Gateway ID
    - `default_security_group_id` (string)
    - `private_route_table_ids` (list(string))
    - `public_route_table_ids` (list(string))
  - **Wiring Notes**: `vpc_id` feeds into ALB, EC2, security group modules; `public_subnets` feed into ALB `subnets`; `private_subnets` feed into EC2 `subnet_id`; VPC is typically looked up via data source in consumer stacks rather than created -- use `create_zone = false` pattern or `data.aws_vpc`
  - **NOTE FOR CONSUMER STACK**: If the VPC already exists, do NOT use this module. Use `data.aws_vpc` and `data.aws_subnets` data sources directly as raw resources (data sources are permitted in consumer code for lookups).

### Supporting Modules

#### 10. ACM (Certificates)

- **Module**: `app.terraform.io/hashi-demos-apj/acm/aws` v6.1.1
  - **Purpose**: ACM certificates with Route53 DNS validation
  - **Key Inputs**: `domain_name`, `zone_id`, `validation_method`, `subject_alternative_names`, `wait_for_validation`
  - **Key Outputs**: `acm_certificate_arn` (feeds into ALB listener `certificate_arn`), `acm_certificate_status`

#### 11. Route53 (DNS)

- **Module**: `app.terraform.io/hashi-demos-apj/route53/aws` v6.1.1
  - **Purpose**: Route53 hosted zones and DNS records
  - **Key Inputs**: `name`, `records` (map of record definitions with alias support), `create_zone` (set false for existing zones)
  - **Key Outputs**: `id` (zone ID), `name_servers`, `records`, `arn`
  - **Wiring Notes**: Zone ID feeds into ACM `zone_id`; records use ALB `dns_name` + `zone_id` for alias records

#### 12. Autoscaling

- **Module**: `app.terraform.io/hashi-demos-apj/autoscaling/aws` v9.0.2
  - **Purpose**: Auto Scaling Group with launch template, scaling policies, schedules, and IAM profile
  - **Provider**: `hashicorp/aws >= 6.12`
  - **Required Inputs**: `name` (string) -- **REQUIRED**
  - **Key Inputs**: `min_size`, `max_size`, `desired_capacity`, `vpc_zone_identifier` (subnet IDs), `image_id`, `instance_type`, `security_groups`, `user_data`, `health_check_type`, `traffic_source_attachments` (for ALB target group attachment), `scaling_policies`, `create_iam_instance_profile`, `iam_role_policies`
  - **Key Outputs**: `autoscaling_group_id`, `autoscaling_group_arn`, `autoscaling_group_name`, `launch_template_id`, `launch_template_arn`, `iam_role_arn`, `iam_instance_profile_arn`
  - **Secure Defaults**: `metadata_options` enforces IMDSv2 (`http_tokens = "required"`, `http_put_response_hop_limit = 1`)
  - **Wiring Notes**: `traffic_source_attachments` references ALB target group ARN from `module.alb.target_groups["key"].arn`; `vpc_zone_identifier` takes private subnet IDs; `security_groups` takes SG IDs

#### 13. KMS (Encryption)

- **Module**: `app.terraform.io/hashi-demos-apj/kms/aws` v4.1.1
  - **Purpose**: KMS keys with key policies, aliases, and grants
  - **Key Inputs**: `description`, `enable_key_rotation` (default: true), `key_users`, `key_administrators`, `aliases`
  - **Key Outputs**: `key_arn` (feeds into S3/DynamoDB/SQS encryption), `key_id`, `aliases`

#### 14. IAM

- **Module**: `app.terraform.io/hashi-demos-apj/iam/aws` v6.2.3
  - **Purpose**: IAM roles, policies, groups, users, OIDC providers (submodule-based)
  - **Submodules**: `//modules/iam-role`, `//modules/iam-policy`, `//modules/iam-role-for-service-accounts`
  - **Wiring Notes**: Use for EC2 instance roles with policies for S3, DynamoDB, SQS, SNS access

### Glue Resources Needed

- **`data.aws_vpc`** -- Look up existing VPC by tags/ID (if VPC already exists)
- **`data.aws_subnets`** -- Look up existing subnets by VPC ID and tags
- **`data.aws_caller_identity`** -- Get current AWS account ID for IAM policies
- **`data.aws_region`** -- Get current region for ARN construction
- **`data.aws_ami`** -- Look up latest AMI for EC2 instances (alternative to SSM parameter default)
- **No `random_*` resources required** -- all modules support `name` or `name_prefix` inputs

### Cross-Module Wiring Map

```
VPC (data sources)
  |-- vpc_id -----------> ALB.vpc_id
  |-- vpc_id -----------> Security Group.vpc_id
  |-- vpc_id -----------> EC2.security_group_vpc_id
  |-- public_subnets ----> ALB.subnets
  |-- private_subnets ---> EC2.subnet_id / Autoscaling.vpc_zone_identifier

ALB
  |-- arn_suffix --------> CloudWatch metric alarms (dimension)
  |-- dns_name + zone_id -> Route53 alias records
  |-- security_group_id --> EC2 SG ingress (referenced_security_group_id)
  |-- target_groups -----> Autoscaling.traffic_source_attachments

EC2 / Autoscaling
  |-- id ----------------> ALB target_groups.target_id (single instance)
  |-- iam_role_arn ------> IAM policy references

SNS
  |-- topic_arn ---------> CloudWatch alarm_actions
  |-- topic_arn ---------> SQS subscription endpoint

SQS
  |-- queue_arn ---------> SNS subscription endpoint
  |-- queue_url ---------> Application configuration

S3
  |-- s3_bucket_name ----> ALB access_logs.bucket
  |-- s3_bucket_arn -----> IAM policies for EC2 access

DynamoDB
  |-- dynamodb_table_arn -> IAM policies for EC2 access
  |-- dynamodb_table_id --> Application configuration

KMS
  |-- key_arn -----------> S3 server_side_encryption_configuration
  |-- key_arn -----------> DynamoDB server_side_encryption_kms_key_arn
  |-- key_arn -----------> SQS kms_master_key_id
  |-- key_arn -----------> SNS kms_master_key_id

ACM
  |-- acm_certificate_arn -> ALB listeners.certificate_arn
```

### Provider Version Requirements

| Module | Minimum AWS Provider Version |
|--------|------------------------------|
| ALB | >= 6.19 |
| EC2 Instance | >= 6.0 |
| S3 Bucket | >= 6.5 |
| DynamoDB Table | >= 6.13 |
| SQS | >= 6.0 |
| SNS | >= 6.9 |
| CloudWatch | (submodule-based, ~3.0+) |
| Security Group | >= 3.29 |
| VPC | >= 5.53 |
| ACM | >= 6.4 |
| Route53 | >= 6.3 |
| Autoscaling | >= 6.12 |
| KMS | >= 6.11 |
| IAM | (submodule-based) |

**Effective minimum provider version**: `>= 6.19` (driven by ALB module)

### Rationale

All nine core web stack components (ALB, EC2, S3, DynamoDB, SQS, SNS, CloudWatch, Security Group, VPC) have corresponding private registry modules in the `hashi-demos-apj` organization. Additionally, supporting modules for ACM, Route53, Autoscaling, KMS, and IAM are available. All modules are based on the well-maintained `terraform-aws-modules` community modules, ensuring:

1. Consistent input/output naming conventions across modules
2. Compatible type signatures for cross-module wiring (string VPC IDs, list(string) subnet IDs, etc.)
3. Built-in security defaults (IMDSv2, public access blocks, deletion protection)
4. No need to use public registry modules or raw resources

The S3 bucket module has a custom `environment` required input added by the organization, indicating organizational customization on top of the upstream module.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Public registry `terraform-aws-modules/*` | Organization policy requires private registry modules; private versions are available for all needed components |
| Raw AWS resources (aws_lb, aws_instance, etc.) | Consumer constitution prohibits raw resources; modules provide security defaults and consistent interfaces |
| Combined "web stack" mega-module | No such module exists in private registry; composing individual modules provides better flexibility and separation of concerns |
| CloudFront module for CDN | Available (`hashi-demos-apj/cloudfront/aws`) but not requested in requirements; can be added later |
| Lambda module for serverless compute | Available (`hashi-demos-apj/lambda/aws`) but EC2/Autoscaling requested; can substitute if serverless is preferred |

### Sources

- Private registry: `app.terraform.io/hashi-demos-apj` organization, 30 modules total
- Module details retrieved via Terraform Cloud API for each module
- README examples from each module's VCS repository (github.com/hashi-demo-lab/terraform-aws-*)
