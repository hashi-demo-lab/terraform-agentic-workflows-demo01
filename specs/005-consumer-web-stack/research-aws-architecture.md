## Research: AWS architecture patterns for a web application stack in ap-southeast-2

### Decision

Use raw AWS provider resources (data sources for VPC/subnets, managed resources for ALB, EC2, S3, DynamoDB, SQS, SNS, CloudWatch, and security groups) composed with standard wiring patterns -- the ap-southeast-2 region has specific ELB account requirements for S3 access log bucket policies, and the stack benefits from explicit resource-level control for security group chaining and CloudWatch metric dimensions.

### 1. VPC Data Source Lookup Patterns

#### Default VPC Lookup
```hcl
data "aws_vpc" "selected" {
  default = true
}
```

#### Tag-based VPC Lookup
```hcl
data "aws_vpc" "selected" {
  tags = {
    Name = var.vpc_name
  }
}
```

#### Filter-based VPC Lookup
```hcl
data "aws_vpc" "selected" {
  filter {
    name   = "tag:Environment"
    values = [var.environment]
  }
}
```

#### Public Subnets Lookup
```hcl
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }

  tags = {
    Tier = "Public"
  }
}
```

Alternatively, filter by `mapPublicIpOnLaunch`:
```hcl
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}
```

**Key attributes exported:**
- `data.aws_vpc.selected.id` -- string, the VPC ID
- `data.aws_vpc.selected.cidr_block` -- string, the VPC CIDR (needed for security group rules)
- `data.aws_vpc.selected.arn` -- string, the VPC ARN
- `data.aws_subnets.public.ids` -- list(string), all matching subnet IDs

**Design considerations:**
- The consumer should accept `vpc_id` OR `vpc_name` as variables, with an option for `use_default_vpc = true`
- Subnet tag filtering (e.g., `Tier = "Public"`) is the most reliable approach for non-default VPCs
- For default VPCs, all subnets are public by default
- The `aws_subnets` data source returns `ids` as `list(string)` which feeds directly into `aws_lb.subnets`

---

### 2. ALB Access Log Requirements (S3 Bucket Policy)

#### Region-Specific ELB Account ID

For `ap-southeast-2` (Sydney), the ELB service account ID is **783225319266**.

**Critical:** The S3 bucket policy must grant `s3:PutObject` to the ELB service account for the ALB to write access logs. The `data.aws_elb_service_account` data source automatically resolves the correct account ID for the configured region.

```hcl
data "aws_elb_service_account" "main" {}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "alb_logs" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs.arn}/${var.alb_log_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
  }
}
```

#### S3 Bucket Configuration for ALB Access Logs

Required companion resources for the log bucket:
- `aws_s3_bucket` -- the bucket itself
- `aws_s3_bucket_policy` -- ELB service account write permission
- `aws_s3_bucket_public_access_block` -- block all public access
- `aws_s3_bucket_server_side_encryption_configuration` -- SSE-S3 encryption
- `aws_s3_bucket_lifecycle_configuration` -- expire old logs (e.g., 90 days)

**ALB access_logs block:**
```hcl
resource "aws_lb" "web" {
  # ...
  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = var.alb_log_prefix   # e.g., "alb-logs"
    enabled = true
  }
}
```

**Key constraint:** The `access_logs.enabled` defaults to `false` even when a bucket is specified. It must be explicitly set to `true`.

**Prefix format:** When `prefix` is set (e.g., "alb-logs"), ALB writes logs to: `s3://bucket-name/alb-logs/AWSLogs/{account-id}/elasticloadbalancing/{region}/{yyyy}/{mm}/{dd}/`. The bucket policy `resources` path must match this prefix structure.

---

### 3. EC2 User Data for Simple HTTP Server

#### Amazon Linux 2023 with Busybox httpd

```bash
#!/bin/bash
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo "<h1>Hello from $(hostname)</h1>" > /var/www/html/index.html
```

#### Minimal Python HTTP Server (no package install needed)

```bash
#!/bin/bash
mkdir -p /var/www/html
echo "<h1>Hello from $(hostname -f)</h1><p>Region: ap-southeast-2</p>" > /var/www/html/index.html
cd /var/www/html
nohup python3 -m http.server 80 &
```

#### AMI Lookup for Amazon Linux 2023

```hcl
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
```

Alternatively, use SSM parameter store resolution (no data source needed):
```hcl
resource "aws_instance" "web" {
  ami = "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  # ...
}
```

**EC2 Instance key attributes:**
- `instance_type` = `"t3.small"` (burstable, 2 vCPU, 2 GiB)
- `vpc_security_group_ids` = `[aws_security_group.ec2.id]` (NOT `security_groups` which is for EC2-Classic/default VPC only)
- `subnet_id` = pick one public subnet from the data source
- `associate_public_ip_address` = `true` (for public subnet placement)
- `user_data` = the startup script (base64-encoded automatically by Terraform)
- `metadata_options.http_tokens` = `"required"` (enforce IMDSv2 -- security best practice)

---

### 4. CloudWatch Metric Dimensions

#### ALB 5xx Errors

**Namespace:** `AWS/ApplicationELB`
**Metric:** `HTTPCode_ELB_5XX_Count`
**Dimensions:**
```hcl
dimensions = {
  LoadBalancer = aws_lb.web.arn_suffix
}
```

The `arn_suffix` attribute on `aws_lb` gives the value in the format `app/{lb-name}/{hash}` which is exactly what CloudWatch expects.

**Full alarm configuration:**
```hcl
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ALB 5xx errors exceeded threshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.web.arn_suffix
  }
}
```

#### SQS Queue Depth

**Namespace:** `AWS/SQS`
**Metric:** `ApproximateNumberOfMessagesVisible`
**Dimensions:**
```hcl
dimensions = {
  QueueName = aws_sqs_queue.main.name
}
```

Note: SQS dimensions use `QueueName` (the name, NOT the URL or ARN).

**Full alarm configuration:**
```hcl
resource "aws_cloudwatch_metric_alarm" "sqs_depth" {
  alarm_name          = "${var.project}-sqs-queue-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 1000
  alarm_description   = "SQS queue depth exceeded threshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.main.name
  }
}
```

---

### 5. Wiring Patterns -- Component Interconnections

#### Data Flow Diagram

```
Internet -> ALB (public subnets, SG: HTTP 80 from 0.0.0.0/0)
              |
              v
         Target Group (port 80, HTTP)
              |
              v
         EC2 Instance (SG: HTTP 80 from ALB SG only)
              |
              +-> DynamoDB (via IAM instance profile, no SG needed)
              +-> SQS Queue -> Dead Letter Queue
              +-> SNS Topic (operational alerts)
              +-> CloudWatch Alarms -> SNS Topic
```

#### Key Wiring Connections

| Source Output | Target Input | Type |
|--------------|-------------|------|
| `data.aws_vpc.selected.id` | `aws_security_group.*.vpc_id`, `aws_lb_target_group.*.vpc_id` | `string` |
| `data.aws_vpc.selected.cidr_block` | SG ingress `cidr_ipv4` | `string` |
| `data.aws_subnets.public.ids` | `aws_lb.*.subnets` | `list(string)` |
| `data.aws_subnets.public.ids[0]` | `aws_instance.*.subnet_id` | `string` |
| `aws_security_group.alb.id` | `aws_lb.*.security_groups` | `list(string)` (wrap in `[]`) |
| `aws_security_group.ec2.id` | `aws_instance.*.vpc_security_group_ids` | `list(string)` (wrap in `[]`) |
| `aws_lb.web.arn` | `aws_lb_listener.*.load_balancer_arn` | `string` |
| `aws_lb.web.arn_suffix` | CloudWatch dimensions `LoadBalancer` | `string` |
| `aws_lb_target_group.web.arn` | `aws_lb_listener.*.default_action.target_group_arn` | `string` |
| `aws_lb_target_group.web.arn` | `aws_lb_target_group_attachment.*.target_group_arn` | `string` |
| `aws_instance.web.id` | `aws_lb_target_group_attachment.*.target_id` | `string` |
| `aws_s3_bucket.alb_logs.id` | `aws_lb.web.access_logs.bucket` | `string` |
| `aws_sqs_queue.dlq.arn` | `aws_sqs_queue.main.redrive_policy.deadLetterTargetArn` | `string` |
| `aws_sqs_queue.main.name` | CloudWatch dimensions `QueueName` | `string` |
| `aws_sns_topic.alerts.arn` | `aws_cloudwatch_metric_alarm.*.alarm_actions` | `list(string)` (wrap in `[]`) |

#### Resource Creation Order (Implicit Dependencies)

1. **Data sources** (VPC, subnets, AMI, ELB service account, caller identity) -- no dependencies
2. **S3 bucket** + policy + public access block -- depends on caller identity and ELB service account
3. **Security groups** (ALB SG, EC2 SG) -- depends on VPC data source
4. **SNS topic** -- no dependencies
5. **SQS dead letter queue** -- no dependencies
6. **SQS main queue** -- depends on DLQ ARN (for redrive policy)
7. **DynamoDB table** -- no dependencies
8. **ALB** -- depends on subnets, ALB SG, S3 bucket (for access logs)
9. **Target group** -- depends on VPC ID
10. **ALB listener** -- depends on ALB, target group
11. **EC2 instance** -- depends on AMI, subnet, EC2 SG
12. **Target group attachment** -- depends on target group, EC2 instance
13. **CloudWatch alarms** -- depends on ALB (arn_suffix), SQS (name), SNS topic (arn)

---

### 6. Region-Specific Considerations for ap-southeast-2

#### Availability Zones

`ap-southeast-2` has three AZs: `ap-southeast-2a`, `ap-southeast-2b`, `ap-southeast-2c`. ALB requires subnets in at least 2 AZs.

#### ELB Service Account

For `ap-southeast-2`, the ELB service account ID is **783225319266**. Using `data.aws_elb_service_account` is the safest approach as it resolves automatically per region.

#### AMI Availability

Amazon Linux 2023 AMIs are available in `ap-southeast-2`. The SSM parameter path `"/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"` works in this region.

#### Instance Type Availability

`t3.small` is available in all three AZs of `ap-southeast-2`. No constraints.

#### S3 Bucket Naming

S3 bucket names are globally unique. Use a naming convention that includes region and account context (e.g., `${var.project}-alb-logs-${data.aws_caller_identity.current.account_id}-apse2`).

#### Provider Configuration

```hcl
provider "aws" {
  region = "ap-southeast-2"
}
```

---

### 7. Security Group Configuration

#### Recommended Pattern: Separate SGs for ALB and EC2

**ALB Security Group** -- allows HTTP from VPC CIDR (or internet, depending on requirements):
```hcl
resource "aws_security_group" "alb" {
  name        = "${var.project}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = data.aws_vpc.selected.id
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = data.aws_vpc.selected.cidr_block
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
```

**EC2 Security Group** -- allows HTTP ONLY from the ALB SG:
```hcl
resource "aws_security_group" "ec2" {
  name        = "${var.project}-ec2-sg"
  description = "Security group for EC2 instances"
  vpc_id      = data.aws_vpc.selected.id
}

resource "aws_vpc_security_group_ingress_rule" "ec2_from_alb" {
  security_group_id            = aws_security_group.ec2.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 80
  ip_protocol                  = "tcp"
  to_port                      = 80
}

resource "aws_vpc_security_group_egress_rule" "ec2_all" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
```

**Best practice note:** The provider documentation recommends using `aws_vpc_security_group_ingress_rule` and `aws_vpc_security_group_egress_rule` resources (standalone rules) rather than inline `ingress`/`egress` blocks on `aws_security_group`. This avoids conflicts and enables better management of individual rules.

**Traffic flow pattern:**
- ALB SG: ingress HTTP/80 from VPC CIDR, egress all to anywhere
- EC2 SG: ingress HTTP/80 from ALB SG (referenced by security group ID, not CIDR), egress all to anywhere
- This ensures EC2 instances are only reachable via the ALB, never directly from VPC CIDR

---

### 8. SQS with Dead Letter Queue Pattern

```hcl
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project}-dlq"
  message_retention_seconds = 1209600  # 14 days (maximum)
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "main" {
  name                      = "${var.project}-queue"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600  # 4 days
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main.arn]
  })
}
```

**Key attributes:**
- `aws_sqs_queue.main.arn` -- string, the queue ARN (for IAM policies and SNS subscriptions)
- `aws_sqs_queue.main.id` -- string, the queue URL (used for `queue_url` in related resources)
- `aws_sqs_queue.main.name` -- string, the queue name (used in CloudWatch dimensions)

---

### 9. DynamoDB Table Pattern

```hcl
resource "aws_dynamodb_table" "main" {
  name         = "${var.project}-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = var.dynamodb_hash_key

  attribute {
    name = var.dynamodb_hash_key
    type = "S"   # String type
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true  # Uses AWS-managed KMS key
  }

  deletion_protection_enabled = false  # Set true for production

  tags = var.tags
}
```

**Key attributes:**
- `aws_dynamodb_table.main.arn` -- string, the table ARN
- `aws_dynamodb_table.main.name` -- string, the table name
- `billing_mode = "PAY_PER_REQUEST"` means no `read_capacity` or `write_capacity` needed

---

### 10. SNS Topic for Operational Alerts

```hcl
resource "aws_sns_topic" "alerts" {
  name              = "${var.project}-alerts"
  kms_master_key_id = "alias/aws/sns"  # SSE-KMS encryption
}
```

**Key attributes:**
- `aws_sns_topic.alerts.arn` -- string, used as `alarm_actions` and `ok_actions` for CloudWatch alarms

---

### Rationale

This architecture uses standard AWS patterns verified against the Terraform AWS provider v6.36.0 documentation:

1. **Data source lookups** for VPC/subnets are the canonical way to reference existing infrastructure without managing it
2. **Separate security groups** with SG-to-SG references (not CIDR) enforce proper ALB->EC2 traffic flow isolation
3. **ELB service account data source** handles the region-specific account ID for ap-southeast-2 automatically
4. **Standalone SG rules** (`aws_vpc_security_group_ingress_rule`/`aws_vpc_security_group_egress_rule`) are the current best practice per provider docs, avoiding the conflicts and management issues of inline rules
5. **SQS-managed SSE** (`sqs_managed_sse_enabled = true`) provides encryption without KMS key management overhead
6. **CloudWatch alarm dimensions** use `arn_suffix` for ALB (format: `app/name/hash`) and `name` for SQS (queue name string)
7. **`treat_missing_data = "notBreaching"`** prevents alarms firing during periods with no traffic (e.g., low-traffic hours)

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Using inline SG rules (`ingress`/`egress` blocks) | Provider docs explicitly warn against this -- struggles with managing multiple CIDR blocks and conflicts with standalone rule resources |
| Using `security_groups` argument on EC2 | Only works in EC2-Classic/default VPC; `vpc_security_group_ids` is the correct argument for VPC instances |
| Hardcoding ELB service account ID for ap-southeast-2 | Brittle; `data.aws_elb_service_account` resolves per-region automatically |
| Using `aws_s3_bucket` deprecated inline arguments (acl, policy, etc.) | All deprecated; use separate companion resources (`aws_s3_bucket_policy`, `aws_s3_bucket_public_access_block`, etc.) |
| FIFO SQS queue | Standard queue is appropriate for this use case; FIFO adds complexity and cost for no benefit |
| CloudWatch composite alarms | Unnecessary complexity for two independent metrics; simple metric alarms suffice |
| Using `user_data_base64` | Not needed for simple bash scripts; `user_data` handles UTF-8 strings automatically |

### Sources

- Terraform AWS Provider v6.36.0: `aws_vpc` data source documentation
- Terraform AWS Provider v6.36.0: `aws_subnets` data source documentation
- Terraform AWS Provider v6.36.0: `aws_lb` resource documentation
- Terraform AWS Provider v6.36.0: `aws_lb_listener` resource documentation
- Terraform AWS Provider v6.36.0: `aws_lb_target_group` resource documentation
- Terraform AWS Provider v6.36.0: `aws_lb_target_group_attachment` resource documentation
- Terraform AWS Provider v6.36.0: `aws_instance` resource documentation
- Terraform AWS Provider v6.36.0: `aws_s3_bucket` resource documentation
- Terraform AWS Provider v6.36.0: `aws_s3_bucket_policy` resource documentation
- Terraform AWS Provider v6.36.0: `aws_s3_bucket_public_access_block` resource documentation
- Terraform AWS Provider v6.36.0: `aws_dynamodb_table` resource documentation
- Terraform AWS Provider v6.36.0: `aws_sqs_queue` resource documentation
- Terraform AWS Provider v6.36.0: `aws_sns_topic` resource documentation
- Terraform AWS Provider v6.36.0: `aws_sns_topic_subscription` resource documentation
- Terraform AWS Provider v6.36.0: `aws_cloudwatch_metric_alarm` resource documentation
- Terraform AWS Provider v6.36.0: `aws_security_group` resource documentation
- Terraform AWS Provider v6.36.0: `aws_elb_service_account` data source documentation
- Terraform AWS Provider v6.36.0: `aws_ami` data source documentation
- AWS Documentation: ELB Access Logging account IDs per region
- AWS Documentation: CloudWatch metrics for ApplicationELB and SQS namespaces
