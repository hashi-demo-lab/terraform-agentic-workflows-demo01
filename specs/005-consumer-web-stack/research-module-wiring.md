## Research: Module wiring patterns for composing a web application stack from private registry modules

### Decision

Use the ALB module's built-in `target_groups` and `additional_target_group_attachments` inputs for EC2-to-ALB wiring, the CloudWatch `metric-alarm` submodule with SNS topic ARN for alarm actions, and centralize all cross-module references through `locals.tf` to ensure type-safe wiring with no transformations needed for the primary data flows.

### Modules Identified

- **Primary Module**: `app.terraform.io/hashi-demos-apj/alb/aws` v10.1.0
  - **Purpose**: Application Load Balancer with target groups, listeners, and security group
  - **Key Inputs**: `name` (string), `vpc_id` (string), `subnets` (list(string)), `security_groups` (list(string)), `access_logs` (object({bucket=string, enabled=optional(bool), prefix=optional(string)})), `target_groups` (map(object)), `listeners` (map(object)), `additional_target_group_attachments` (map(object)), `tags` (map(string))
  - **Key Outputs**: `arn` (string - ALB ARN), `arn_suffix` (string - for CloudWatch dimensions), `dns_name` (string), `security_group_id` (string), `target_groups` (map - target group attributes including ARN and ARN suffix), `listeners` (map)
  - **Secure Defaults**: `drop_invalid_header_fields = true`, `enable_deletion_protection = true`, `enable_cross_zone_load_balancing = true`

- **Supporting Modules**:
  - `app.terraform.io/hashi-demos-apj/ec2-instance/aws` v6.1.4 -- EC2 instances with security group and IAM role
  - `app.terraform.io/hashi-demos-apj/security-group/aws` v5.3.1 -- Standalone security groups (for shared/external SG definitions)
  - `app.terraform.io/hashi-demos-apj/s3-bucket/aws` v6.0.0 -- S3 bucket for ALB access logs
  - `app.terraform.io/hashi-demos-apj/cloudwatch/aws` v5.7.2 -- CloudWatch metric alarms (via submodules)
  - `app.terraform.io/hashi-demos-apj/sns/aws` v7.0.0 -- SNS topic for alarm notifications
  - `app.terraform.io/hashi-demos-apj/sqs/aws` v5.1.0 -- SQS queue for application messaging
  - `app.terraform.io/hashi-demos-apj/vpc/aws` v6.5.0 -- VPC (or use data sources for pre-existing VPC)

- **Glue Resources Needed**:
  - `aws_lb_target_group_attachment` -- Wire EC2 instance IDs to ALB target groups (when EC2 is provisioned separately from ALB module)
  - `data.aws_vpc` -- Look up existing VPC by ID or tags (if VPC is pre-existing)
  - `data.aws_subnets` -- Look up subnets by VPC ID and tags (if VPC is pre-existing)

- **Wiring Considerations**: See detailed sections below

---

### 1. Type Compatibility Between Module Outputs and Inputs

#### Critical Type Mappings

| Source | Output | Output Type | Target | Input | Input Type | Compatible? | Transformation |
|--------|--------|-------------|--------|-------|------------|-------------|----------------|
| VPC data source | `data.aws_vpc.this.id` | `string` | ALB module | `vpc_id` | `string` | Yes | Direct |
| VPC data source | `data.aws_subnets.public.ids` | `list(string)` | ALB module | `subnets` | `list(string)` | Yes | Direct |
| VPC data source | `data.aws_subnets.private.ids` | `list(string)` | EC2 module | `subnet_id` | `string` | No -- needs element | `element(data.aws_subnets.private.ids, 0)` |
| VPC data source | `data.aws_vpc.this.cidr_block` | `string` | Security Group | `ingress_cidr_blocks` | `list(string)` | No -- needs wrapping | `[data.aws_vpc.this.cidr_block]` |
| S3 bucket module | `s3_bucket_name` | `string` | ALB module | `access_logs.bucket` | `string` | Yes | Direct (via object) |
| Security Group module | `security_group_id` | `string` | ALB module | `security_groups` | `list(string)` | No -- needs wrapping | `[module.alb_sg.security_group_id]` |
| Security Group module | `security_group_id` | `string` | EC2 module | `vpc_security_group_ids` | `list(string)` | No -- needs wrapping | `[module.ec2_sg.security_group_id]` |
| ALB module | `target_groups` | `map(object)` | TG attachment | `target_group_arn` | `string` | Needs lookup | `module.alb.target_groups["key"].arn` |
| ALB module | `arn_suffix` | `string` | CloudWatch alarm | `dimensions.LoadBalancer` | `string` | Yes | Direct |
| ALB module | `target_groups["key"].arn_suffix` | `string` | CloudWatch alarm | `dimensions.TargetGroup` | `string` | Yes | Direct |
| SNS module | `topic_arn` | `string` | CloudWatch alarm | `alarm_actions` | `list(string)` | No -- needs wrapping | `[module.sns.topic_arn]` |
| SQS module | `queue_url` | `string` | CloudWatch alarm | `dimensions` (custom) | `string` | Yes | Direct |
| SQS module | `queue_name` | `string` | CloudWatch alarm | `dimensions.QueueName` | `string` | Yes | Direct |
| EC2 module | `id` | `string` | TG attachment | `target_id` | `string` | Yes | Direct |

#### Key Type Gotchas

1. **string-to-list wrapping**: Many modules accept `list(string)` for security groups and subnets, but upstream outputs are often single `string` values. Always wrap with `[value]`.
2. **map output access**: ALB `target_groups` output is a `map` -- access individual target groups via the map key used in `target_groups` input (e.g., `module.alb.target_groups["web"].arn`).
3. **data source `ids` is `list(string)`**: The `aws_subnets` data source returns `ids` as `list(string)`, which directly feeds into ALB `subnets` input.
4. **ALB `access_logs` is an object, not a string**: Must pass `{ bucket = module.s3_bucket.s3_bucket_name }`, not just the bucket name.

---

### 2. Common Transformation Patterns

#### Wrapping (string to list)

```hcl
# Single SG ID -> list of SG IDs
security_groups = [module.alb_sg.security_group_id]

# Single CIDR -> list of CIDRs
ingress_cidr_blocks = [data.aws_vpc.this.cidr_block]

# Single ARN -> list for alarm_actions
alarm_actions = [module.sns_alerts.topic_arn]
```

#### Element Selection (list to string)

```hcl
# Pick first subnet for a single EC2 instance
subnet_id = element(data.aws_subnets.private.ids, 0)

# Or using index notation
subnet_id = data.aws_subnets.private.ids[0]
```

#### Map Lookup (accessing nested output attributes)

```hcl
# Access specific target group from ALB module output map
target_group_arn = module.alb.target_groups["web"].arn

# Access ALB arn_suffix for CloudWatch dimensions
dimensions = {
  LoadBalancer = module.alb.arn_suffix
  TargetGroup  = module.alb.target_groups["web"].arn_suffix
}
```

#### Flatten / Concat (merging lists)

```hcl
# Merge multiple security group IDs from different modules
vpc_security_group_ids = concat(
  [module.ec2_sg.security_group_id],
  var.additional_security_group_ids
)

# Merge subnet lists (rare but possible)
all_subnet_ids = concat(
  data.aws_subnets.public.ids,
  data.aws_subnets.private.ids
)
```

#### toset / tolist (type coercion)

```hcl
# for_each requires a set
for_each = toset(data.aws_subnets.private.ids)

# Some modules require list, but you have a set
subnets = tolist(var.subnet_ids_set)
```

---

### 3. Naming Convention Patterns Using Locals

```hcl
locals {
  # ---------- Naming ----------
  name_prefix = "${var.project_name}-${var.environment}"

  # Component-specific names
  alb_name          = "${local.name_prefix}-alb"
  ec2_name          = "${local.name_prefix}-web"
  alb_sg_name       = "${local.name_prefix}-alb-sg"
  ec2_sg_name       = "${local.name_prefix}-ec2-sg"
  log_bucket_name   = "${local.name_prefix}-alb-logs"
  sns_topic_name    = "${local.name_prefix}-alerts"
  sqs_queue_name    = "${local.name_prefix}-queue"
  cw_alarm_prefix   = "${local.name_prefix}"

  # ---------- Tags ----------
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
  }
}
```

**Best practice**: Define `name_prefix` once in locals, derive all resource names from it. This ensures consistency across all modules and makes environment promotion trivial (just change `var.environment`).

---

### 4. ALB Target Group to EC2 Instance Wiring

There are two patterns for attaching EC2 instances to ALB target groups.

#### Pattern A: Built-in attachment via ALB module (preferred for single instances)

The ALB module supports `target_id` directly in the `target_groups` map:

```hcl
module "alb" {
  source  = "app.terraform.io/hashi-demos-apj/alb/aws"
  version = "~> 10.1"

  name    = local.alb_name
  vpc_id  = data.aws_vpc.this.id
  subnets = data.aws_subnets.public.ids

  target_groups = {
    web = {
      name_prefix = "web-"
      protocol    = "HTTP"
      port        = 80
      target_type = "instance"
      target_id   = module.ec2_web.id    # Direct reference
      vpc_id      = data.aws_vpc.this.id

      health_check = {
        enabled             = true
        path                = "/health"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        interval            = 30
        matcher             = "200"
      }
    }
  }

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "web"   # References key in target_groups map
      }
    }
  }
}
```

#### Pattern B: Separate attachment via `additional_target_group_attachments` (preferred for multiple instances)

When EC2 instances are created with `for_each`, use the ALB module's `additional_target_group_attachments`:

```hcl
module "alb" {
  source  = "app.terraform.io/hashi-demos-apj/alb/aws"
  version = "~> 10.1"

  target_groups = {
    web = {
      name_prefix       = "web-"
      protocol          = "HTTP"
      port              = 80
      target_type       = "instance"
      create_attachment = false    # IMPORTANT: disable built-in attachment
      vpc_id            = data.aws_vpc.this.id
    }
  }

  additional_target_group_attachments = {
    instance_1 = {
      target_group_key = "web"
      target_id        = module.ec2_web["one"].id
      port             = 80
    }
    instance_2 = {
      target_group_key = "web"
      target_id        = module.ec2_web["two"].id
      port             = 80
    }
  }
}
```

#### Pattern C: Raw glue resource (when EC2 is provisioned entirely outside ALB module)

```hcl
resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = module.alb.target_groups["web"].arn
  target_id        = module.ec2_web.id
  port             = 80
}
```

**Recommendation**: Pattern A for single-instance stacks, Pattern B for multi-instance. Pattern C only if there is a strong reason to decouple (e.g., instances managed in a separate workspace).

---

### 5. CloudWatch Alarms to SNS Topic Wiring

The CloudWatch module uses submodules. The `metric-alarm` submodule is used for individual alarms.

#### Metric Alarm with SNS Actions

```hcl
module "alb_5xx_alarm" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.7"

  alarm_name          = "${local.cw_alarm_prefix}-alb-5xx"
  alarm_description   = "ALB 5XX error rate exceeds threshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 10
  period              = 60
  statistic           = "Sum"

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_ELB_5XX_Count"

  dimensions = {
    LoadBalancer = module.alb.arn_suffix  # string, direct
  }

  alarm_actions = [module.sns_alerts.topic_arn]  # list(string)
  ok_actions    = [module.sns_alerts.topic_arn]
}
```

#### ALB Healthy Host Count Alarm

```hcl
module "alb_healthy_hosts_alarm" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.7"

  alarm_name          = "${local.cw_alarm_prefix}-unhealthy-hosts"
  alarm_description   = "No healthy targets in ALB target group"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  threshold           = 1
  period              = 60
  statistic           = "Minimum"

  namespace   = "AWS/ApplicationELB"
  metric_name = "HealthyHostCount"

  dimensions = {
    LoadBalancer = module.alb.arn_suffix
    TargetGroup  = module.alb.target_groups["web"].arn_suffix
  }

  alarm_actions = [module.sns_alerts.topic_arn]
  ok_actions    = [module.sns_alerts.topic_arn]
}
```

#### SQS Queue Depth Alarm

```hcl
module "sqs_depth_alarm" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.7"

  alarm_name          = "${local.cw_alarm_prefix}-sqs-depth"
  alarm_description   = "SQS queue depth exceeds threshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 100
  period              = 300
  statistic           = "Average"

  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"

  dimensions = {
    QueueName = module.sqs.queue_name  # string, direct
  }

  alarm_actions = [module.sns_alerts.topic_arn]
}
```

**Key points for CloudWatch alarm dimensions**:
- ALB dimensions use `arn_suffix` (e.g., `app/my-alb/abc123`), NOT the full ARN
- SQS dimensions use `queue_name`, NOT `queue_url` or `queue_arn`
- `alarm_actions` and `ok_actions` accept `list(string)` of ARNs -- wrap the SNS topic ARN in a list

---

### 6. Data Flow Ordering and Implicit Dependencies

#### Dependency Graph

```
Level 0 (no dependencies):
  - data.aws_vpc.this
  - module.s3_alb_logs
  - module.sns_alerts
  - module.sqs

Level 1 (depends on Level 0):
  - data.aws_subnets.public  (depends on data.aws_vpc)
  - data.aws_subnets.private (depends on data.aws_vpc)
  - module.alb_sg            (depends on data.aws_vpc for vpc_id)
  - module.ec2_sg            (depends on data.aws_vpc for vpc_id)

Level 2 (depends on Level 1):
  - module.alb               (depends on subnets, alb_sg, s3_alb_logs, vpc)
  - module.ec2_web           (depends on subnets, ec2_sg)

Level 3 (depends on Level 2):
  - aws_lb_target_group_attachment (depends on alb target_groups, ec2 id)
    OR wiring is built into module.alb via target_id / additional_target_group_attachments

Level 4 (depends on Level 2-3):
  - module.alb_5xx_alarm           (depends on alb.arn_suffix, sns.topic_arn)
  - module.alb_healthy_hosts_alarm (depends on alb.arn_suffix, alb.target_groups, sns.topic_arn)
  - module.sqs_depth_alarm         (depends on sqs.queue_name, sns.topic_arn)
```

#### Implicit vs Explicit Dependencies

Terraform resolves most dependencies **implicitly** through output-to-input references. No `depends_on` is needed for:
- `module.alb` referencing `data.aws_subnets.public.ids` -- Terraform knows the data source must complete first
- `module.alb` referencing `module.s3_alb_logs.s3_bucket_name` -- Terraform knows the S3 module must complete first
- CloudWatch alarms referencing `module.alb.arn_suffix` -- Terraform knows the ALB must exist first

`depends_on` is needed ONLY for side-effect dependencies that are not visible in the configuration graph (extremely rare in consumer code).

---

### 7. Best Practices for locals.tf to Centralize Wiring Logic

#### Recommended locals.tf Structure

```hcl
locals {
  # =============================================
  # Section 1: Naming
  # =============================================
  name_prefix = "${var.project_name}-${var.environment}"

  alb_name        = "${local.name_prefix}-alb"
  ec2_name        = "${local.name_prefix}-web"
  alb_sg_name     = "${local.name_prefix}-alb-sg"
  ec2_sg_name     = "${local.name_prefix}-ec2-sg"
  log_bucket_name = "${local.name_prefix}-alb-logs-${random_id.suffix.hex}"
  sns_topic_name  = "${local.name_prefix}-alerts"
  sqs_queue_name  = "${local.name_prefix}-queue"

  # =============================================
  # Section 2: Network wiring
  # =============================================
  vpc_id             = data.aws_vpc.this.id
  vpc_cidr           = data.aws_vpc.this.cidr_block
  public_subnet_ids  = data.aws_subnets.public.ids
  private_subnet_ids = data.aws_subnets.private.ids

  # =============================================
  # Section 3: Security group wiring
  # =============================================
  alb_security_group_ids = [module.alb_sg.security_group_id]
  ec2_security_group_ids = [module.ec2_sg.security_group_id]

  # =============================================
  # Section 4: Monitoring wiring
  # =============================================
  alarm_actions = [module.sns_alerts.topic_arn]

  # =============================================
  # Section 5: Tags
  # =============================================
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
  }
}
```

#### Why Centralize in locals.tf

1. **Single point of change**: If the VPC data source changes from `data.aws_vpc.this` to `module.vpc`, only `locals.tf` needs updating.
2. **Type transformation isolation**: All `[string]` wrapping and `element()` calls live in one file.
3. **Readability**: Module calls in `main.tf` reference `local.vpc_id` instead of `data.aws_vpc.this.id`.
4. **Reuse**: `local.alarm_actions` is defined once and used by all CloudWatch alarm modules.
5. **Naming consistency**: All names derived from `local.name_prefix` guarantees uniform naming.

#### Anti-patterns to Avoid

- **Do NOT put module calls in locals.tf** -- locals are for computations, not resource declarations
- **Do NOT create deeply nested locals** -- prefer flat locals over `local.network.vpc_id`
- **Do NOT duplicate values** -- if a value is used once, reference the source directly in main.tf; locals are for values used 2+ times or requiring transformation

---

### S3 Bucket for ALB Access Logs -- Wiring Pattern

The S3 bucket module needs specific configuration for ALB log delivery:

```hcl
module "s3_alb_logs" {
  source  = "app.terraform.io/hashi-demos-apj/s3-bucket/aws"
  version = "~> 6.0"

  bucket      = local.log_bucket_name
  environment = var.environment

  # ALB log delivery requires these policies
  attach_elb_log_delivery_policy = true
  attach_lb_log_delivery_policy  = true

  force_destroy = var.environment != "production"  # Safety for non-prod

  tags = local.common_tags
}
```

Then wire to ALB:

```hcl
module "alb" {
  # ...
  access_logs = {
    bucket  = module.s3_alb_logs.s3_bucket_name   # string -> string
    enabled = true
    prefix  = "alb"
  }
}
```

**Note**: The S3 module's `s3_bucket_name` output (type: `string`) maps directly to the ALB module's `access_logs.bucket` (type: `string`). No transformation needed. The S3 bucket module has a required `environment` input that other modules do not -- ensure it is always provided.

---

### Provider Version Compatibility

| Module | Required AWS Provider | Notes |
|--------|-----------------------|-------|
| ALB v10.1.0 | >= 6.19 | Highest requirement in this stack |
| EC2 v6.1.4 | >= 6.0 | |
| Security Group v5.3.1 | >= 3.29 | Very permissive |
| S3 Bucket v6.0.0 | >= 6.5 | |
| CloudWatch v5.7.2 | Not specified (root) | Submodules may vary |
| SNS v7.0.0 | >= 6.9 | |
| SQS v5.1.0 | >= 6.0 | |
| VPC v6.5.0 | Not captured in summary | |

**Conclusion**: Consumer `required_providers` must specify `aws >= 6.19` to satisfy the ALB module (the highest requirement).

---

### Rationale

All seven modules exist in the `hashi-demos-apj` private registry and share compatible AWS provider constraints. The ALB module (v10.1.0) is the most feature-rich, supporting built-in target group attachments, security group creation, and listener configuration -- eliminating the need for most glue resources. The CloudWatch module provides a `metric-alarm` submodule that accepts `alarm_actions` as `list(string)`, matching the pattern of wrapping the SNS `topic_arn` in a list. Type compatibility analysis confirms that only three transformation patterns are needed across the entire stack: string-to-list wrapping (`[value]`), element selection (`element(list, 0)`), and map key access (`module.alb.target_groups["key"].arn`).

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Raw `aws_lb` + `aws_lb_target_group` resources | Consumer constitution prohibits raw resources; ALB module encapsulates all needed resources |
| Separate `aws_security_group` resources | SG module exists in private registry; raw resources prohibited |
| `aws_cloudwatch_metric_alarm` resource directly | CloudWatch module submodule provides same interface with organizational consistency |
| ALB module's built-in `create_security_group = true` | Could be used, but separate SG modules allow reuse of SG IDs across ALB and EC2 with explicit control |
| Using VPC module instead of data sources | Depends on whether VPC is pre-existing; data sources are lighter-weight for referencing existing infrastructure |

### Sources

- Private registry: `hashi-demos-apj` organization module listing (30 modules)
- `hashi-demos-apj/alb/aws` v10.1.0 -- ALB module inputs/outputs documentation
- `hashi-demos-apj/ec2-instance/aws` v6.1.4 -- EC2 module inputs/outputs documentation
- `hashi-demos-apj/security-group/aws` v5.3.1 -- Security Group module inputs/outputs documentation
- `hashi-demos-apj/s3-bucket/aws` v6.0.0 -- S3 module inputs/outputs documentation
- `hashi-demos-apj/cloudwatch/aws` v5.7.2 -- CloudWatch module README (submodule patterns)
- `hashi-demos-apj/sns/aws` v7.0.0 -- SNS module inputs/outputs documentation
- `hashi-demos-apj/sqs/aws` v5.1.0 -- SQS module inputs/outputs documentation
- AWS provider docs: `aws_lb_target_group_attachment` resource (v6.36.0)
- AWS provider docs: `aws_cloudwatch_metric_alarm` resource (v6.36.0)
- AWS provider docs: `aws_vpc` data source (v6.36.0)
- AWS provider docs: `aws_subnets` data source (v6.36.0)
