# =============================================================================
# Main: Module calls and glue resources
# =============================================================================

# --------------------------------------------------------------------------
# Glue Resources
# --------------------------------------------------------------------------

# Unique suffix for globally unique S3 bucket naming
resource "random_id" "suffix" {
  byte_length = 4
}

# --------------------------------------------------------------------------
# Storage and Messaging (Item B) -- no upstream module dependencies
# --------------------------------------------------------------------------

# S3 bucket for ALB access logs with versioning, encryption, and log delivery policies
module "s3_alb_logs" {
  source  = "app.terraform.io/hashi-demos-apj/s3-bucket/aws"
  version = "~> 6.0"

  bucket      = local.log_bucket_name
  environment = var.environment

  # Versioning enabled per FR-5
  versioning = {
    enabled = true
  }

  # AES256 server-side encryption per FR-5 and CIS AWS 2.1.1
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  # [SECURITY OVERRIDE] Dev environment: force destroy enabled for sandbox cleanup (REL09-BP01)
  force_destroy = true

  # ALB log delivery policies per FR-5 and CIS AWS 2.6
  attach_elb_log_delivery_policy = true
  attach_lb_log_delivery_policy  = true

  # Module secure defaults for public access block are honoured -- DO NOT override:
  # block_public_acls = true, block_public_policy = true,
  # ignore_public_acls = true, restrict_public_buckets = true

  tags = merge(local.common_tags, {
    Component = "storage"
  })
}

# DynamoDB table with on-demand billing, PITR, and encryption per FR-6
module "dynamodb" {
  source  = "app.terraform.io/hashi-demos-apj/dynamodb-table/aws"
  version = "~> 5.2"

  name     = local.dynamodb_table_name
  hash_key = var.dynamodb_hash_key

  attributes = [
    {
      name = var.dynamodb_hash_key
      type = "S"
    }
  ]

  billing_mode                   = "PAY_PER_REQUEST"
  point_in_time_recovery_enabled = true
  server_side_encryption_enabled = true

  # Dev environment: deletion protection disabled for easy teardown (REL09-BP01)
  deletion_protection_enabled = false

  tags = merge(local.common_tags, {
    Component = "data"
  })
}

# SQS queue with managed SSE, 4-day retention, DLQ per FR-7
module "sqs" {
  source  = "app.terraform.io/hashi-demos-apj/sqs/aws"
  version = "~> 5.1"

  name = local.sqs_queue_name

  # Module secure defaults honoured -- DO NOT override:
  # sqs_managed_sse_enabled = true, dlq_sqs_managed_sse_enabled = true

  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  message_retention_seconds  = var.sqs_message_retention_seconds

  # Dead-letter queue with max receive count per FR-7
  create_dlq = true
  redrive_policy = {
    maxReceiveCount = var.sqs_max_receive_count
  }

  tags = merge(local.common_tags, {
    Component = "messaging"
  })
}

# SNS topic for operational alerts per FR-8
module "sns_alerts" {
  source  = "app.terraform.io/hashi-demos-apj/sns/aws"
  version = "~> 7.0"

  name = local.sns_topic_name

  # No KMS encryption -- dev environment, operational alerts contain metric names
  # and thresholds only, no PII or secrets (SEC08-BP01 N/A justification)

  tags = merge(local.common_tags, {
    Component = "monitoring"
  })
}

# --------------------------------------------------------------------------
# Networking and Compute (Item C) -- VPC data source wired
# --------------------------------------------------------------------------

# Security group for EC2: HTTP ingress from VPC CIDR, all egress per FR-4
module "ec2_sg" {
  source  = "app.terraform.io/hashi-demos-apj/security-group/aws"
  version = "~> 5.3"

  name        = local.ec2_sg_name
  description = "Security group for web server EC2 instance"
  vpc_id      = data.aws_vpc.selected.id

  # HTTP (port 80) ingress from VPC CIDR block per FR-4 and SEC05-BP02
  ingress_rules       = ["http-80-tcp"]
  ingress_cidr_blocks = [data.aws_vpc.selected.cidr_block]

  # All egress allowed
  egress_rules = ["all-all"]

  tags = merge(local.common_tags, {
    Component = "networking"
  })
}

# Single EC2 instance running HTTP application per FR-3
module "ec2_web" {
  source  = "app.terraform.io/hashi-demos-apj/ec2-instance/aws"
  version = "~> 6.1"

  name          = local.ec2_name
  instance_type = var.instance_type

  # Place in first public subnet per FR-3
  subnet_id = data.aws_subnets.public.ids[0]

  # Wire security group from ec2_sg module output -> list(string) wrapping
  vpc_security_group_ids = [module.ec2_sg.security_group_id]

  # Disable module-created SG since we use the standalone ec2_sg module
  create_security_group = false

  # Public IP for dev access per SEC05-BP02
  associate_public_ip_address = true

  # User data script for HTTP server bootstrap per FR-3
  user_data = var.user_data

  # Module secure defaults honoured -- DO NOT override:
  # metadata_options.http_tokens = "required" (IMDSv2 enforced per CIS AWS 5.6)

  # No IAM instance profile -- application does not require AWS API access in dev (CIS AWS 1.16)
  create_iam_instance_profile = false

  tags = merge(local.common_tags, {
    Component = "compute"
  })
}

# --------------------------------------------------------------------------
# Load Balancer and Monitoring (Item D) -- ALB, CloudWatch alarms
# --------------------------------------------------------------------------

# Application Load Balancer with HTTP listener, target group, and access logging per FR-2
module "alb" {
  source  = "app.terraform.io/hashi-demos-apj/alb/aws"
  version = "~> 10.1"

  name               = local.alb_name
  load_balancer_type = "application"
  vpc_id             = data.aws_vpc.selected.id
  subnets            = data.aws_subnets.public.ids

  # [SECURITY OVERRIDE] Dev environment: deletion protection disabled for easy teardown (REL09-BP01)
  enable_deletion_protection = false

  # Module secure defaults honoured -- DO NOT override:
  # drop_invalid_header_fields = true (SEC06-BP01)
  # enable_cross_zone_load_balancing = true

  # ALB module creates its own security group per architectural decision
  create_security_group = true

  # HTTP/80 ingress from anywhere for public-facing ALB per SEC05-BP03
  security_group_ingress_rules = {
    http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "HTTP from internet"
    }
  }

  # Allow all egress for health checks and target communication
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "All egress"
    }
  }

  # Target group with EC2 instance attached (Pattern A: built-in attachment) per wiring table
  target_groups = {
    web = {
      name_prefix = "web-"
      protocol    = "HTTP"
      port        = 80
      target_type = "instance"
      target_id   = module.ec2_web.id # Wiring: module.ec2_web.id -> target_groups.web.target_id
      vpc_id      = data.aws_vpc.selected.id

      health_check = {
        enabled             = true
        path                = "/"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        interval            = 30
        matcher             = "200"
      }
    }
  }

  # HTTP listener on port 80 forwarding to the web target group per FR-2
  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"

      # [SECURITY OVERRIDE] Dev environment: HTTP-only, HTTPS/TLS out of scope.
      # Internal-only HTTP traffic between ALB and EC2.
      forward = {
        target_group_key = "web" # References key in target_groups map
      }
    }
  }

  # ALB access logs to S3 bucket per CIS AWS 2.6
  # Wiring: module.s3_alb_logs.s3_bucket_name -> access_logs.bucket
  access_logs = {
    bucket  = module.s3_alb_logs.s3_bucket_name
    enabled = true
    prefix  = "alb"
  }

  tags = merge(local.common_tags, {
    Component = "networking"
  })
}

# CloudWatch metric alarm for ALB 5xx errors per FR-9
module "alb_5xx_alarm" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.7"

  alarm_name          = "${local.name_prefix}-alb-5xx"
  alarm_description   = "ALB 5XX error count exceeds threshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 10
  period              = 300
  statistic           = "Sum"

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_ELB_5XX_Count"

  # Wiring: module.alb.arn_suffix -> dimensions.LoadBalancer
  dimensions = {
    LoadBalancer = module.alb.arn_suffix
  }

  # Wiring: module.sns_alerts.topic_arn -> alarm_actions (string -> list wrapping)
  alarm_actions = [module.sns_alerts.topic_arn]
  ok_actions    = [module.sns_alerts.topic_arn]

  tags = merge(local.common_tags, {
    Component = "monitoring"
  })
}

# CloudWatch metric alarm for SQS queue depth per FR-9
module "sqs_depth_alarm" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.7"

  alarm_name          = "${local.name_prefix}-sqs-depth"
  alarm_description   = "SQS queue depth exceeds threshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 100
  period              = 300
  statistic           = "Average"

  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"

  # Wiring: module.sqs.queue_name -> dimensions.QueueName
  dimensions = {
    QueueName = module.sqs.queue_name
  }

  # Wiring: module.sns_alerts.topic_arn -> alarm_actions (string -> list wrapping)
  alarm_actions = [module.sns_alerts.topic_arn]
  ok_actions    = [module.sns_alerts.topic_arn]

  tags = merge(local.common_tags, {
    Component = "monitoring"
  })
}
