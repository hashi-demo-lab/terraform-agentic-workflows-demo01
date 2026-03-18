## Research: Module Composition and Wiring Patterns for Web Application Stack

### Decision

Use `locals` blocks for naming/transformation, direct `module.<name>.<output>` references for data flow, provider `default_tags` for tag propagation, and explicit type coercion (`tolist()`, `toset()`) where module output/input types differ. All wiring patterns are derived from studying the `terraform-aws-modules/*` family (ALB v10.5, S3 v5.10, Security Group v5.3, Autoscaling v9.2, DynamoDB v5.5, SQS v5.2, SNS v7.1, CloudWatch v5.7).

---

### 1. Data Source to Module Wiring

#### VPC Data Source

The `aws_vpc` data source returns a VPC object with `id` (string), `cidr_block` (string), and `arn` (string). The `aws_subnets` data source returns `ids` as `list(string)`.

**Pattern: Look up existing VPC and subnets by tags, then wire into modules.**

```hcl
data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

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

**Key outputs and their types:**
- `data.aws_vpc.selected.id` -- `string` -- feeds into module `vpc_id` inputs
- `data.aws_vpc.selected.cidr_block` -- `string` -- feeds into security group CIDR rules
- `data.aws_subnets.public.ids` -- `list(string)` -- feeds into ALB `subnets` input

**Wiring into ALB module:**
```hcl
module "alb" {
  source  = "app.terraform.io/<org>/alb/aws"
  version = "~> 10.5"

  vpc_id  = data.aws_vpc.selected.id    # string -> string (direct)
  subnets = data.aws_subnets.public.ids  # list(string) -> list(string) (direct)
}
```

**Wiring into Security Group module:**
```hcl
module "ec2_sg" {
  source  = "app.terraform.io/<org>/security-group/aws"
  version = "~> 5.3"

  vpc_id = data.aws_vpc.selected.id  # string -> string (direct)
  ingress_cidr_blocks = [data.aws_vpc.selected.cidr_block]  # string wrapped in list
}
```

**Important**: `data.aws_vpc.selected.cidr_block` is a `string`, but `ingress_cidr_blocks` expects `list(string)`. Wrap it: `[data.aws_vpc.selected.cidr_block]`.

---

### 2. Module to Module Wiring

#### ALB -> EC2/ASG (Target Group ARN)

The ALB module (terraform-aws-modules/alb v10.5) outputs `target_groups` as a **map of objects**. Each key in the map corresponds to the key used in the `target_groups` input map.

```hcl
# ALB module outputs
output "target_groups" {
  description = "Map of target groups created and their attributes"
}
```

**To get the target group ARN for attachment:**
```hcl
# The target_groups output is a map keyed by the same keys used in the input
module.alb.target_groups["web"].arn
module.alb.target_groups["web"].arn_suffix  # For CloudWatch dimensions
```

**For EC2 instances using the ALB's built-in attachment (`create_attachment = true`):**
The ALB module can attach targets directly via the `target_id` attribute within the `target_groups` map input. No separate `aws_lb_target_group_attachment` resource is needed.

```hcl
module "alb" {
  # ...
  target_groups = {
    web = {
      name_prefix      = "web-"
      protocol         = "HTTP"
      port             = 80
      target_type      = "instance"
      target_id        = module.ec2_instance.id  # Direct wiring
      create_attachment = true
    }
  }
}
```

**Alternatively, for additional target group attachments outside the target_groups map:**
```hcl
module "alb" {
  # ...
  additional_target_group_attachments = {
    ec2_instance = {
      target_group_key = "web"
      target_id        = module.ec2_instance.id
      port             = 80
    }
  }
}
```

#### S3 Bucket -> ALB Access Logs

The S3 bucket module (terraform-aws-modules/s3-bucket v5.10) outputs `s3_bucket_id` as `string` (the bucket name). The ALB module accepts `access_logs` as an object.

```hcl
module "log_bucket" {
  source  = "app.terraform.io/<org>/s3-bucket/aws"
  version = "~> 5.10"

  bucket = "${local.name_prefix}-alb-logs"

  # CRITICAL: Must attach the ALB/NLB log delivery policy for ALB access logs
  attach_lb_log_delivery_policy = true     # Enables the correct bucket policy
  attach_elb_log_delivery_policy = true    # For Classic LB compatibility

  force_destroy = true  # Dev environment
}

module "alb" {
  # ...
  access_logs = {
    bucket  = module.log_bucket.s3_bucket_id  # string -> string (bucket name)
    enabled = true
    prefix  = "alb"
  }
}
```

**Important**: The S3 module outputs `s3_bucket_id` (bucket name, type `string`) and `s3_bucket_arn` (ARN, type `string`). The ALB `access_logs.bucket` expects the bucket **name** (not ARN), so use `s3_bucket_id`.

#### ALB Security Group -> EC2 Security Group

The ALB module (v10.5) creates its own security group when `create_security_group = true` and exposes it via `security_group_id` output (type `string`).

**Wiring ALB SG to EC2 ingress (allow traffic from ALB):**
```hcl
module "ec2_sg" {
  source  = "app.terraform.io/<org>/security-group/aws"
  version = "~> 5.3"

  vpc_id = data.aws_vpc.selected.id

  ingress_with_source_security_group_id = [
    {
      from_port                = 80
      to_port                  = 80
      protocol                 = "tcp"
      description              = "HTTP from ALB"
      source_security_group_id = module.alb.security_group_id  # string -> string
    }
  ]
}
```

#### CloudWatch Alarms -> ALB (arn_suffix dimension)

```hcl
# CloudWatch metric alarm for ALB 5xx errors
module "alb_5xx_alarm" {
  source = "app.terraform.io/<org>/cloudwatch/aws//modules/metric-alarm"

  alarm_name  = "${local.name_prefix}-alb-5xx"
  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_ELB_5XX_Count"
  dimensions = {
    LoadBalancer = module.alb.arn_suffix  # string -> string
  }
  alarm_actions = [module.sns.topic_arn]  # string -> list(string) - wrap in list
}
```

**Important**: `alarm_actions` expects `list(string)` but `module.sns.topic_arn` is `string`. Wrap it: `[module.sns.topic_arn]`.

#### CloudWatch Alarms -> SQS (queue name dimension)

```hcl
module "sqs_depth_alarm" {
  source = "app.terraform.io/<org>/cloudwatch/aws//modules/metric-alarm"

  alarm_name  = "${local.name_prefix}-sqs-depth"
  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"
  dimensions = {
    QueueName = module.sqs.queue_name  # string -> string
  }
  alarm_actions = [module.sns.topic_arn]
}
```

---

### 3. Type Compatibility Patterns

#### Common Mismatches and Resolutions

| Source Output | Source Type | Target Input | Target Type | Resolution |
|---------------|-----------|--------------|-------------|------------|
| `data.aws_subnets.*.ids` | `list(string)` | `module.alb.subnets` | `list(string)` | Direct (compatible) |
| `data.aws_vpc.*.cidr_block` | `string` | `ingress_cidr_blocks` | `list(string)` | Wrap: `[data.aws_vpc.*.cidr_block]` |
| `module.alb.security_group_id` | `string` | `security_groups` | `list(string)` | Wrap: `[module.alb.security_group_id]` |
| `module.sns.topic_arn` | `string` | `alarm_actions` | `list(string)` | Wrap: `[module.sns.topic_arn]` |
| `module.alb.target_groups` | `map(object)` | target group ARN | `string` | Index: `module.alb.target_groups["key"].arn` |
| `data.aws_subnets.*.ids` | `list(string)` | Needs first element | `string` | Index: `data.aws_subnets.*.ids[0]` |
| Set output | `set(string)` | List input | `list(string)` | Convert: `tolist(module.x.set_output)` |
| List output | `list(string)` | Set input | `set(string)` | Convert: `toset(module.x.list_output)` |

#### Type Coercion Functions

- `tolist()` -- converts sets to lists (preserves order not guaranteed)
- `toset()` -- converts lists to sets (deduplicates, loses order)
- `tostring()` -- converts numbers to strings
- `tonumber()` -- converts strings to numbers
- `[value]` -- wraps scalar in single-element list (most common pattern)
- `element(list, 0)` or `list[0]` -- extracts first element from list

---

### 4. Locals for Computed Wiring

#### Naming Convention Pattern

```hcl
locals {
  name_prefix = "${var.project}-${var.environment}"

  # Standard tags applied via provider default_tags + module tags
  common_tags = {
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terraform"
    Application = var.application_name
  }
}
```

#### Subnet Selection Pattern

```hcl
locals {
  # First subnet for single-instance placement
  primary_subnet_id = data.aws_subnets.public.ids[0]

  # All public subnets for ALB
  public_subnet_ids = data.aws_subnets.public.ids

  # VPC context
  vpc_id   = data.aws_vpc.selected.id
  vpc_cidr = data.aws_vpc.selected.cidr_block
}
```

#### Cross-Module Reference Pattern

```hcl
locals {
  # ALB outputs reused in multiple places
  alb_arn_suffix       = module.alb.arn_suffix
  alb_security_group_id = module.alb.security_group_id

  # SNS for alarm routing
  alarm_sns_topic_arn = module.sns.topic_arn
}
```

**Best Practices for locals:**
1. Group locals by purpose (naming, networking, security, monitoring)
2. Use locals to give semantic names to data source outputs
3. Use locals for any value referenced more than twice
4. Never embed complex expressions directly in module inputs -- extract to locals
5. Use locals for conditional logic (e.g., `local.enable_logging ? module.bucket.id : null`)

---

### 5. Naming Patterns

The consumer constitution mandates `{project}-{environment}-{component}` naming. Implementation pattern:

```hcl
variable "project" {
  type    = string
  default = "webstack"
}

variable "environment" {
  type    = string
  default = "dev"
}

locals {
  name_prefix = "${var.project}-${var.environment}"
}

# Usage in module calls
module "alb" {
  name = "${local.name_prefix}-alb"  # "webstack-dev-alb"
}

module "s3_bucket" {
  bucket = "${local.name_prefix}-logs-${random_string.suffix.result}"
  # S3 requires globally unique names, so add random suffix
}

module "dynamodb_table" {
  name = "${local.name_prefix}-sessions"
}

module "sqs" {
  name = "${local.name_prefix}-tasks"
}

module "sns" {
  name = "${local.name_prefix}-alerts"
}
```

**Key rules:**
- S3 bucket names must be globally unique -- use `random_string` suffix
- ALB names max 32 chars, alphanumeric and hyphens only
- DynamoDB table names max 255 chars
- SQS queue names max 80 chars (256 for FIFO with `.fifo` suffix)
- SNS topic names max 256 chars

---

### 6. Tag Propagation

#### Provider default_tags

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project
      ManagedBy   = "terraform"
      Application = var.application_name
    }
  }
}
```

**How provider `default_tags` interact with module `tags` inputs:**

1. Provider `default_tags` are applied to **all** AWS resources automatically
2. Module `tags` inputs are applied to resources within the module
3. Module `tags` **override** provider `default_tags` for same-key tags
4. The merge order is: `provider.default_tags` < `module.tags` < resource-level `tags`

**Recommendation:**
- Set base tags (Environment, Project, ManagedBy, Application) in `provider.default_tags`
- Use module `tags` only for module-specific tags (e.g., `Purpose = "ALB Access Logs"`)
- This avoids tag duplication and ensures consistency

```hcl
module "log_bucket" {
  source = "app.terraform.io/<org>/s3-bucket/aws"
  tags = {
    Purpose = "ALB access logs"  # Module-specific, supplements default_tags
  }
}
```

**Known gotcha**: When using `default_tags`, the AWS provider shows perpetual diffs if you also pass the same tags via module `tags` input. Avoid duplicating `default_tags` values in module `tags`.

---

### 7. Security Group Wiring

#### Pattern: Layered Security Groups

A web application stack typically needs multiple security groups wired together:

```
Internet -> ALB SG (ingress 80/443 from 0.0.0.0/0)
              |
              v
          EC2 SG (ingress 80 from ALB SG)
              |
              v
          DB SG (ingress 3306/5432 from EC2 SG) [if applicable]
```

#### ALB Module Built-in Security Group

The ALB module v10.5 creates its own SG by default (`create_security_group = true`). Configure rules via:

```hcl
module "alb" {
  # ...
  create_security_group = true

  security_group_ingress_rules = {
    http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "HTTP from internet"
    }
  }

  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "All egress"
    }
  }
}
```

#### Separate Security Group Module

Using `terraform-aws-modules/security-group/aws` v5.3.1:

```hcl
module "ec2_sg" {
  source  = "app.terraform.io/<org>/security-group/aws"
  version = "~> 5.3"

  name        = "${local.name_prefix}-ec2"
  description = "Security group for EC2 web servers"
  vpc_id      = local.vpc_id

  # Rule-based ingress (predefined rules)
  ingress_rules = ["http-80-tcp"]
  ingress_cidr_blocks = [local.vpc_cidr]

  # Source SG-based ingress (cross-module wiring)
  ingress_with_source_security_group_id = [
    {
      from_port                = 80
      to_port                  = 80
      protocol                 = "tcp"
      description              = "HTTP from ALB"
      source_security_group_id = module.alb.security_group_id
    }
  ]

  egress_rules = ["all-all"]

  tags = { Purpose = "EC2 web server" }
}
```

**Cross-module SG reference types:**
- `security_group_id` output: `string` -- used in `source_security_group_id` inputs
- `security_groups` input on ALB: `list(string)` -- wrap single SG: `[module.sg.security_group_id]`
- ALB module's `security_group_ingress_rules`: uses `referenced_security_group_id` (string)

---

### 8. Conditional Module Patterns

#### Enable/Disable via `count`

```hcl
variable "enable_monitoring" {
  type    = bool
  default = true
}

module "sns" {
  source  = "app.terraform.io/<org>/sns/aws"
  version = "~> 7.1"
  count   = var.enable_monitoring ? 1 : 0

  name = "${local.name_prefix}-alerts"
}

# Reference conditional module output safely
locals {
  alarm_sns_topic_arn = var.enable_monitoring ? module.sns[0].topic_arn : null
}
```

#### Module-Level Create Flag

Many `terraform-aws-modules/*` modules support a `create` boolean input:

```hcl
module "alb" {
  source = "app.terraform.io/<org>/alb/aws"
  create = var.enable_alb  # false = no resources created
}

module "dynamodb_table" {
  source       = "app.terraform.io/<org>/dynamodb-table/aws"
  create_table = var.enable_dynamodb  # false = no table created
}

module "sqs" {
  source = "app.terraform.io/<org>/sqs/aws"
  create = var.enable_sqs  # false = no queue created
}
```

**Key modules with `create` flags:**
- ALB: `create` (bool, default `true`)
- S3: `create_bucket` (bool, default `true`)
- DynamoDB: `create_table` (bool, default `true`)
- SQS: `create` (bool, default `true`)
- SNS: `create` (bool, default `true`)
- Security Group: `create` (bool, default `true`)

**Conditional downstream wiring:**
```hcl
module "alb_alarm" {
  source = "app.terraform.io/<org>/cloudwatch/aws//modules/metric-alarm"
  count  = var.enable_monitoring && var.enable_alb ? 1 : 0

  dimensions = {
    LoadBalancer = module.alb.arn_suffix
  }
  alarm_actions = var.enable_monitoring ? [module.sns[0].topic_arn] : []
}
```

---

### Module Interface Summary

| Module | Key Inputs (types) | Key Outputs (types) | Notes |
|--------|-------------------|---------------------|-------|
| **ALB** (v10.5) | `vpc_id` (string), `subnets` (list(string)), `security_groups` (list(string)), `listeners` (map(object)), `target_groups` (map(object)), `access_logs` (object), `tags` (map(string)) | `id` (string), `arn` (string), `arn_suffix` (string), `dns_name` (string), `security_group_id` (string), `target_groups` (map(object)), `listeners` (map(object)) | Creates own SG by default; requires AWS >= 6.28 |
| **S3 Bucket** (v5.10) | `bucket` (string), `tags` (map(string)), `attach_lb_log_delivery_policy` (bool), `attach_elb_log_delivery_policy` (bool), `force_destroy` (bool) | `s3_bucket_id` (string = bucket name), `s3_bucket_arn` (string), `s3_bucket_bucket_domain_name` (string) | Use `s3_bucket_id` for ALB access_logs.bucket |
| **Security Group** (v5.3) | `vpc_id` (string), `name` (string), `ingress_rules` (list(string)), `ingress_cidr_blocks` (list(string)), `ingress_with_source_security_group_id` (list(map(string))), `egress_rules` (list(string)), `tags` (map(string)) | `security_group_id` (string), `security_group_arn` (string), `security_group_name` (string) | Has predefined rule names like "http-80-tcp" |
| **DynamoDB** (v5.5) | `name` (string), `hash_key` (string), `attributes` (list(map(string))), `billing_mode` (string), `tags` (map(string)) | `dynamodb_table_id` (string), `dynamodb_table_arn` (string) | PAY_PER_REQUEST default |
| **SQS** (v5.2) | `name` (string), `create_dlq` (bool), `tags` (map(string)) | `queue_arn` (string), `queue_id` (string = URL), `queue_name` (string), `dead_letter_queue_arn` (string) | Use `queue_name` for CloudWatch dimensions |
| **SNS** (v7.1) | `name` (string), `tags` (map(string)) | `topic_arn` (string), `topic_id` (string = ARN), `topic_name` (string) | topic_arn == topic_id |
| **CloudWatch** (v5.7 submodules) | `alarm_name` (string), `namespace` (string), `metric_name` (string), `dimensions` (map(string)), `alarm_actions` (list(string)) | `cloudwatch_metric_alarm_arn` (string), `cloudwatch_metric_alarm_id` (string) | Uses submodules: `metric-alarm`, `log-group` |

---

### Glue Resources Needed

Per the consumer constitution, only these raw resource types are permitted:

- **`random_string`**: For globally unique S3 bucket name suffix
- **`random_id`**: Alternative to `random_string` for shorter identifiers

```hcl
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  bucket_name = "${local.name_prefix}-logs-${random_string.suffix.result}"
}
```

No `null_resource` or `terraform_data` needed for standard web stack wiring.

---

### Rationale

All wiring patterns are derived from studying the `terraform-aws-modules/*` family, the most widely downloaded Terraform modules (ALB: 45M+, S3: 186M+, Security Group: 123M+, DynamoDB: 26M+, SQS: 42M+, SNS: 15M+, CloudWatch: 21M+). These modules share consistent conventions:

1. **String-typed IDs** for cross-module references (vpc_id, security_group_id, bucket name)
2. **Map-of-objects** for complex resources (target_groups, listeners, subscriptions)
3. **`create` flags** for conditional composition
4. **`tags` map(string)** on every module for supplemental tagging
5. **`name` or `name_prefix`** inputs for naming control

The consumer constitution (Section 2.5) mandates direct module references, explicit type coercion, and locals for complex transformations. All patterns above comply with these rules.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Raw `aws_lb`, `aws_instance` resources | Consumer constitution prohibits raw resources; modules provide secure defaults |
| Hardcoded resource names | Violates naming convention; breaks multi-environment deployment |
| Passing tags via every module call | Provider `default_tags` handles base tags; module `tags` only for specifics |
| Using `depends_on` for ordering | Constitution prefers explicit data flow via outputs/inputs |
| Storing VPC ID in variables only | Data sources allow dynamic lookup, reducing hardcoded infrastructure coupling |
| `for_each` on modules instead of `count` | `for_each` preferred for multiple instances; `count` sufficient for enable/disable |

### Sources

- Public Registry: `terraform-aws-modules/alb/aws` v10.5.0 (45.8M downloads) -- inputs/outputs documentation
- Public Registry: `terraform-aws-modules/s3-bucket/aws` v5.10.0 (186M downloads) -- S3 + ALB log delivery pattern
- Public Registry: `terraform-aws-modules/security-group/aws` v5.3.1 (123M downloads) -- cross-SG reference patterns
- Public Registry: `terraform-aws-modules/autoscaling/aws` v9.2.0 (20.1M downloads) -- target group attachment patterns
- Public Registry: `terraform-aws-modules/dynamodb-table/aws` v5.5.0 (26.5M downloads) -- table configuration
- Public Registry: `terraform-aws-modules/sqs/aws` v5.2.1 (42.6M downloads) -- DLQ wiring pattern
- Public Registry: `terraform-aws-modules/sns/aws` v7.1.0 (15.6M downloads) -- notification topic + subscription
- Public Registry: `terraform-aws-modules/cloudwatch/aws` v5.7.2 (21.7M downloads) -- metric-alarm submodule
- AWS Provider: `aws_vpc` data source (doc ID 11672151) -- VPC lookup attributes
- AWS Provider: `aws_subnets` data source (doc ID 11672143) -- subnet ID list retrieval
- Consumer Constitution: `/workspace/.foundations/memory/consumer-constitution.md` -- Sections 2.1, 2.2, 2.5, 3.3
