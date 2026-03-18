## Research: AWS Architecture Patterns for Web Application Stack in ap-southeast-2

### Decision

Use raw glue resources for ALB, EC2, SQS, CloudWatch, and security groups since these are consumer-level wiring between private registry modules -- the architecture follows standard ALB-to-EC2 target group attachment, SQS with DLQ redrive policy, and CloudWatch metric alarms using `AWS/ApplicationELB` and `AWS/SQS` namespaces with region-specific ELB account ID `783225319266` for S3 access log delivery in ap-southeast-2.

### 1. ALB + EC2 Integration Pattern

#### Resource Chain

```
aws_lb (ALB) --> aws_lb_listener (HTTP:80) --> aws_lb_target_group (instance, HTTP:80) --> aws_lb_target_group_attachment --> aws_instance
```

#### ALB Resource (`aws_lb`)

- **Key Arguments**:
  - `name` (optional, max 32 chars) -- unique within account
  - `internal` (optional, default `false`) -- set `false` for public-facing
  - `load_balancer_type` (optional, default `"application"`) -- use `"application"` for ALB
  - `security_groups` (optional) -- list of SG IDs, required for ALB type
  - `subnets` (optional) -- list of subnet IDs, minimum 2 AZs required
  - `enable_deletion_protection` (optional, default `false`) -- set `false` for dev
  - `drop_invalid_header_fields` (optional, default `false`) -- consider `true` for security
  - `desync_mitigation_mode` (optional, default `"defensive"`) -- good default
  - `access_logs` block -- see section 2 below
- **Key Outputs**:
  - `arn` (string) -- full ARN of the load balancer
  - `arn_suffix` (string) -- ARN suffix for CloudWatch Metrics dimensions
  - `dns_name` (string) -- DNS name for the ALB
  - `zone_id` (string) -- for Route 53 alias records
- **Timeouts**: create/update/delete all default 10m

#### Target Group (`aws_lb_target_group`)

- **Key Arguments**:
  - `name` (optional, max 32 chars, forces new)
  - `port` (required for instance type) -- `80`
  - `protocol` (required for instance type) -- `"HTTP"`
  - `target_type` (optional, default `"instance"`) -- use `"instance"` for EC2
  - `vpc_id` (required for instance type) -- VPC ID from data source
  - `health_check` block:
    - `enabled` (default `true`)
    - `healthy_threshold` (default `3`, range 2-10)
    - `unhealthy_threshold` (default `3`, range 2-10)
    - `interval` (default `30`, range 5-300 seconds)
    - `timeout` (default `6` for HTTP)
    - `path` (default `"/"`) -- health check endpoint
    - `port` (default `"traffic-port"`)
    - `protocol` (default `"HTTP"`)
    - `matcher` (default `"200"`, range 200-499 for ALB)
- **Key Outputs**:
  - `arn` (string) -- ARN of the target group
  - `arn_suffix` (string) -- ARN suffix for CloudWatch Metrics dimensions

#### Target Group Attachment (`aws_lb_target_group_attachment`)

- **Key Arguments**:
  - `target_group_arn` (required) -- from `aws_lb_target_group.*.arn`
  - `target_id` (required) -- from `aws_instance.*.id`
  - `port` (optional) -- `80`
- **Pattern for single instance**:
  ```hcl
  resource "aws_lb_target_group_attachment" "web" {
    target_group_arn = aws_lb_target_group.web.arn
    target_id        = aws_instance.web.id
    port             = 80
  }
  ```

#### Listener (`aws_lb_listener`)

- **Key Arguments**:
  - `load_balancer_arn` (required) -- from `aws_lb.*.arn`
  - `port` (optional) -- `80` for HTTP
  - `protocol` (optional, default `"HTTP"`)
  - `default_action` block (required):
    - `type = "forward"`
    - `target_group_arn` -- from `aws_lb_target_group.*.arn`
- **HTTP Listener Pattern** (port 80, forward to target group):
  ```hcl
  resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.web.arn
    port              = 80
    protocol          = "HTTP"

    default_action {
      type             = "forward"
      target_group_arn = aws_lb_target_group.web.arn
    }
  }
  ```

#### Listener Rule (`aws_lb_listener_rule`)

Not required for this use case since the default action on the listener handles forwarding. Listener rules are only needed for path-based or host-based routing.

### 2. ALB Access Logging to S3

#### ELB Account ID for ap-southeast-2

The AWS ELB service uses regional account IDs for writing access logs to S3. For `ap-southeast-2` (Sydney), the ELB account ID is `783225319266`.

**Best practice**: Use the `data.aws_elb_service_account` data source to dynamically resolve the regional account ID rather than hardcoding:

```hcl
data "aws_elb_service_account" "current" {}
```

This returns:
- `id` -- the AWS account ID for ELB in the current region
- `arn` -- the full ARN (`arn:aws:iam::783225319266:root` for ap-southeast-2)

#### S3 Bucket Policy for ALB Log Delivery

The S3 bucket must have a policy granting `s3:PutObject` permission to the ELB service account. The policy document pattern:

```hcl
data "aws_iam_policy_document" "alb_logs" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.current.arn]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/*"]
  }
}
```

**Important notes**:
- The bucket must exist BEFORE enabling access logs on the ALB
- The `access_logs` block on `aws_lb` requires `enabled = true` explicitly (defaults to `false` even when bucket is specified)
- The `prefix` in `access_logs` is optional; logs go to root if not configured
- ALB log path pattern: `{bucket}/{prefix}/AWSLogs/{account-id}/elasticloadbalancing/{region}/{yyyy}/{mm}/{dd}/`

#### ALB Access Logs Configuration

```hcl
resource "aws_lb" "web" {
  # ...
  access_logs {
    bucket  = aws_s3_bucket.logs.id
    prefix  = "alb-logs"
    enabled = true
  }
}
```

### 3. VPC Data Source Patterns

#### Looking Up Existing VPC

**By tag name**:
```hcl
data "aws_vpc" "selected" {
  tags = {
    Name = "my-vpc"
  }
}
```

**By ID variable**:
```hcl
data "aws_vpc" "selected" {
  id = var.vpc_id
}
```

**Default VPC**:
```hcl
data "aws_vpc" "default" {
  default = true
}
```

**Key outputs from `data.aws_vpc`**:
- `id` (string) -- VPC ID
- `cidr_block` (string) -- primary CIDR block
- `arn` (string) -- VPC ARN
- `enable_dns_support` (bool)
- `enable_dns_hostnames` (bool)
- `main_route_table_id` (string)

#### Looking Up Subnets

**Public subnets by VPC and tag**:
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

**By tag:Name pattern**:
```hcl
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  filter {
    name   = "tag:Name"
    values = ["*public*"]
  }
}
```

**Key outputs from `data.aws_subnets`**:
- `ids` (list of string) -- list of all matching subnet IDs

**Best practice**: The consumer prompt requires at least 2 subnets in 2 AZs. Use the `data.aws_subnets` data source with VPC ID filter and tier/public tag to get the list. Use `data.aws_subnets.public.ids` directly for ALB subnets, and `data.aws_subnets.public.ids[0]` for the EC2 instance.

### 4. Security Group Patterns

#### Best Practice: Separate Rules Resources

AWS provider docs recommend using `aws_vpc_security_group_ingress_rule` and `aws_vpc_security_group_egress_rule` instead of inline `ingress`/`egress` blocks on `aws_security_group`. This avoids conflicts and simplifies management.

#### ALB Security Group

The ALB needs to accept HTTP traffic from the internet (or VPC CIDR):

```hcl
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = data.aws_vpc.selected.id
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"  # or VPC CIDR for internal
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

#### EC2 Security Group (behind ALB)

Per the prompt: HTTP (port 80) ingress from VPC CIDR, all egress:

```hcl
resource "aws_security_group" "ec2" {
  name        = "${var.name_prefix}-ec2-sg"
  description = "Security group for EC2 web instances"
  vpc_id      = data.aws_vpc.selected.id
}

resource "aws_vpc_security_group_ingress_rule" "ec2_http_from_vpc" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = data.aws_vpc.selected.cidr_block
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
  description       = "Allow HTTP from VPC CIDR"
}

resource "aws_vpc_security_group_egress_rule" "ec2_all" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound traffic"
}
```

**Key arguments for `aws_vpc_security_group_ingress_rule`**:
- `security_group_id` (required) -- the SG to attach the rule to
- `cidr_ipv4` (optional) -- source CIDR
- `referenced_security_group_id` (optional) -- source SG (alternative to CIDR, for SG-to-SG rules)
- `from_port` / `to_port` (optional) -- port range
- `ip_protocol` (required) -- `"tcp"`, `"udp"`, `"-1"` (all)

**Important note from provider docs**: Terraform removes the default `ALLOW ALL` egress rule when creating a security group in a VPC. You must explicitly create egress rules.

### 5. CloudWatch Alarms for ALB

#### Namespace and Metric Details

- **Namespace**: `AWS/ApplicationELB`
- **Key Metric**: `HTTPCode_ELB_5XX_Count`
- **Dimensions**:
  - `LoadBalancer` -- use `aws_lb.*.arn_suffix` (format: `app/{lb-name}/{hash}`)
  - Optionally also `TargetGroup` -- use `aws_lb_target_group.*.arn_suffix`

#### ALB 5xx Alarm Pattern

```hcl
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.name_prefix}-alb-5xx-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300          # 5 minutes
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

**Important**: Use `treat_missing_data = "notBreaching"` for 5xx alarms, because when there are no errors, there is no data point -- this should not trigger an alarm.

**Other useful ALB metrics**:
- `HTTPCode_Target_5XX_Count` -- 5xx from targets (backend errors)
- `HealthyHostCount` / `UnHealthyHostCount` -- target health
- `RequestCount` -- total requests
- `TargetResponseTime` -- latency

### 6. CloudWatch Alarms for SQS

#### Namespace and Metric Details

- **Namespace**: `AWS/SQS`
- **Key Metric**: `ApproximateNumberOfMessagesVisible`
- **Dimensions**:
  - `QueueName` -- the SQS queue name (NOT the URL or ARN)

#### SQS Queue Depth Alarm Pattern

```hcl
resource "aws_cloudwatch_metric_alarm" "sqs_queue_depth" {
  alarm_name          = "${var.name_prefix}-sqs-queue-depth"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300          # 5 minutes
  statistic           = "Average"
  threshold           = 100
  alarm_description   = "SQS queue depth exceeded threshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.main.name
  }
}
```

**Important**: The dimension uses `QueueName` (the simple name), not the URL or ARN. Access the queue name via `aws_sqs_queue.main.name`.

**Other useful SQS metrics**:
- `ApproximateNumberOfMessagesNotVisible` -- messages in-flight
- `ApproximateAgeOfOldestMessage` -- processing lag
- `NumberOfMessagesSent` / `NumberOfMessagesReceived`

### 7. SQS + DLQ Pattern

#### Two-Queue Pattern

Create the DLQ first, then reference it in the main queue's `redrive_policy`. Also configure the DLQ's `redrive_allow_policy` to restrict which queues can send to it.

```hcl
# Dead Letter Queue
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-dlq"
  message_retention_seconds = 1209600  # 14 days (max retention for DLQ)
  sqs_managed_sse_enabled   = true

  tags = local.common_tags
}

# Main Queue
resource "aws_sqs_queue" "main" {
  name                       = "${var.name_prefix}-queue"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 345600  # 4 days
  receive_wait_time_seconds  = 0
  visibility_timeout_seconds = 30
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })

  tags = local.common_tags
}

# Redrive allow policy on DLQ
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main.arn]
  })
}
```

**Key configuration notes**:
- `redrive_policy` is JSON-encoded with `deadLetterTargetArn` and `maxReceiveCount` (must be integer, not string)
- `maxReceiveCount = 5` means after 5 failed receive attempts, the message goes to the DLQ
- DLQ should have longer retention (14 days) than the main queue for investigation
- `sqs_managed_sse_enabled = true` enables SSE-SQS encryption (simpler than KMS, no key management)
- Alternative: Use separate `aws_sqs_queue_redrive_policy` resource instead of inline `redrive_policy` argument, which is preferred per AWS provider docs to avoid ordering issues

#### Inline vs Separate Resource

The provider docs note: "It is preferred to use the `aws_sqs_queue_redrive_policy` resource instead." However, the inline `redrive_policy` argument works fine for simple cases. The separate resource is better when you have circular dependencies (DLQ needs main queue ARN for allow policy, main queue needs DLQ ARN for redrive policy).

### 8. EC2 User Data for Simple HTTP Server

#### Minimal User Data Script (Amazon Linux 2023)

```bash
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo "<h1>Hello from $(hostname)</h1>" > /var/www/html/index.html
```

#### Alternative: Using Busybox/Netcat (ultra-minimal)

```bash
#!/bin/bash
while true; do
  echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n<h1>Hello from $(hostname)</h1>" | nc -l -p 80 -q 1
done &
```

#### Terraform Integration

```hcl
resource "aws_instance" "web" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.small"
  subnet_id                   = data.aws_subnets.public.ids[0]
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Hello from $(hostname)</h1>" > /var/www/html/index.html
  EOF

  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 enforced
    http_put_response_hop_limit = 1
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-web"
  })
}
```

**Security note**: Always set `http_tokens = "required"` to enforce IMDSv2 on EC2 instances.

#### AMI Lookup Pattern

```hcl
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
```

Alternatively, use SSM parameter: `ami = "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"`

### Wiring Summary

| Source | Output | Destination | Input |
|--------|--------|-------------|-------|
| `data.aws_vpc.selected` | `id` | `aws_security_group.*` | `vpc_id` |
| `data.aws_vpc.selected` | `cidr_block` | `aws_vpc_security_group_ingress_rule.ec2_http` | `cidr_ipv4` |
| `data.aws_subnets.public` | `ids` | `aws_lb.web` | `subnets` |
| `data.aws_subnets.public` | `ids[0]` | `aws_instance.web` | `subnet_id` |
| `aws_security_group.alb` | `id` | `aws_lb.web` | `security_groups` |
| `aws_security_group.ec2` | `id` | `aws_instance.web` | `vpc_security_group_ids` |
| `aws_lb.web` | `arn` | `aws_lb_listener.http` | `load_balancer_arn` |
| `aws_lb.web` | `arn_suffix` | `aws_cloudwatch_metric_alarm.alb_5xx` | `dimensions.LoadBalancer` |
| `aws_lb_target_group.web` | `arn` | `aws_lb_listener.http` | `default_action.target_group_arn` |
| `aws_lb_target_group.web` | `arn` | `aws_lb_target_group_attachment.web` | `target_group_arn` |
| `aws_instance.web` | `id` | `aws_lb_target_group_attachment.web` | `target_id` |
| `aws_s3_bucket.logs` | `id` | `aws_lb.web` | `access_logs.bucket` |
| `data.aws_elb_service_account.current` | `arn` | `aws_s3_bucket_policy.logs` | policy principal |
| `aws_sqs_queue.dlq` | `arn` | `aws_sqs_queue.main` | `redrive_policy.deadLetterTargetArn` |
| `aws_sqs_queue.main` | `name` | `aws_cloudwatch_metric_alarm.sqs_depth` | `dimensions.QueueName` |
| `aws_sns_topic.alerts` | `arn` | `aws_cloudwatch_metric_alarm.*` | `alarm_actions` / `ok_actions` |

### Region-Specific Details (ap-southeast-2)

| Item | Value |
|------|-------|
| ELB Service Account ID | `783225319266` |
| ELB Service Account ARN | `arn:aws:iam::783225319266:root` |
| Data source alternative | `data.aws_elb_service_account.current` (auto-resolves) |
| Available AZs | `ap-southeast-2a`, `ap-southeast-2b`, `ap-southeast-2c` |
| AMI resolution | Use `data.aws_ami` with `owners = ["amazon"]` or SSM parameter |

### Rationale

All architecture patterns are based on current AWS provider v6.36.0 documentation. Key design decisions:
1. **Separate SG rule resources** over inline rules -- per provider docs best practice, avoids conflicts
2. **`data.aws_elb_service_account`** over hardcoded account IDs -- automatically resolves per region
3. **`treat_missing_data = "notBreaching"`** for error count alarms -- prevents false alarms during quiet periods
4. **IMDSv2 enforcement** on EC2 -- security best practice
5. **SQS managed SSE** over KMS -- simpler, no key rotation management, sufficient for dev
6. **DLQ with 14-day retention** -- ensures failed messages are preserved for debugging

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| NLB instead of ALB | ALB provides HTTP-level features (health checks on path, access logs) needed for web apps |
| Auto Scaling Group instead of single EC2 | Prompt specifies single instance for dev simplicity |
| HTTPS listener with ACM certificate | Prompt specifies HTTP on port 80; HTTPS adds cost and complexity for dev |
| KMS encryption for SQS | SQS managed SSE is simpler and sufficient for dev environments |
| Inline security group rules | Provider docs explicitly recommend separate rule resources |
| Hardcoded ELB account IDs | `data.aws_elb_service_account` is more maintainable and region-portable |
| `aws_sqs_queue_redrive_policy` resource | Inline `redrive_policy` is sufficient for simple linear DLQ chain without circular deps |

### Sources

- HashiCorp AWS Provider v6.36.0: `aws_lb` resource documentation
- HashiCorp AWS Provider v6.36.0: `aws_lb_target_group` resource documentation
- HashiCorp AWS Provider v6.36.0: `aws_lb_target_group_attachment` resource documentation
- HashiCorp AWS Provider v6.36.0: `aws_lb_listener` resource documentation
- HashiCorp AWS Provider v6.36.0: `aws_lb_listener_rule` resource documentation
- HashiCorp AWS Provider v6.36.0: `aws_instance` resource documentation
- HashiCorp AWS Provider v6.36.0: `aws_security_group` resource documentation
- HashiCorp AWS Provider v6.36.0: `aws_vpc_security_group_ingress_rule` resource documentation
- HashiCorp AWS Provider v6.36.0: `aws_vpc_security_group_egress_rule` resource documentation
- HashiCorp AWS Provider v6.36.0: `aws_sqs_queue` resource documentation
- HashiCorp AWS Provider v6.36.0: `aws_sqs_queue_redrive_policy` resource documentation
- HashiCorp AWS Provider v6.36.0: `aws_sqs_queue_redrive_allow_policy` resource documentation
- HashiCorp AWS Provider v6.36.0: `aws_cloudwatch_metric_alarm` resource documentation
- HashiCorp AWS Provider v6.36.0: `aws_s3_bucket_policy` resource documentation
- HashiCorp AWS Provider v6.36.0: `data.aws_vpc` data source documentation
- HashiCorp AWS Provider v6.36.0: `data.aws_subnets` data source documentation
- HashiCorp AWS Provider v6.36.0: `data.aws_elb_service_account` data source documentation
- AWS Docs: ELB access log delivery account IDs by region
- AWS Docs: CloudWatch metrics for ApplicationELB namespace
- AWS Docs: CloudWatch metrics for SQS namespace
