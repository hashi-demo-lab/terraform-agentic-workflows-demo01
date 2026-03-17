provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ── Shared tags for consistent visibility across all resources ──

locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terraform"
    Application = "consumer-uplift-demo"
  }
}

# ── Networking ──

module "vpc" {
  source  = "app.terraform.io/hashi-demos-apj/vpc/aws"
  version = "6.5.0"

  name = "${var.name_prefix}-${var.environment}"
  cidr = var.vpc_cidr

  azs            = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets = [cidrsubnet(var.vpc_cidr, 8, 1), cidrsubnet(var.vpc_cidr, 8, 2)]

  enable_dns_hostnames = true
  enable_dns_support   = true
  enable_nat_gateway   = false

  public_subnet_tags = {
    Purpose = "public"
  }

  tags = merge(local.common_tags, {
    Purpose = "networking"
  })
}

# ── Security ──

module "ec2_sg" {
  source  = "app.terraform.io/hashi-demos-apj/security-group/aws"
  version = "5.3.1"

  name        = "${var.name_prefix}-${var.environment}-ec2"
  description = "EC2 app server - HTTP from VPC, all egress"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "HTTP from VPC"
      cidr_blocks = var.vpc_cidr
    }
  ]

  egress_rules = ["all-all"]

  tags = merge(local.common_tags, {
    Purpose = "ec2-security"
  })
}

# ── Compute: Load Balancer ──

module "alb" {
  source  = "app.terraform.io/hashi-demos-apj/alb/aws"
  version = "10.1.0"

  name    = "${var.name_prefix}-${var.environment}"
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  enable_deletion_protection = false

  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      description = "HTTP from internet"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = var.vpc_cidr
    }
  }

  access_logs = {
    bucket  = module.demo_bucket.s3_bucket_id
    prefix  = "alb-logs"
    enabled = true
  }

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "app"
      }
    }
  }

  target_groups = {
    app = {
      name_prefix       = "app-"
      protocol          = "HTTP"
      port              = 80
      target_type       = "instance"
      create_attachment = false

      health_check = {
        enabled             = true
        path                = "/"
        healthy_threshold   = 2
        unhealthy_threshold = 3
        interval            = 30
      }
    }
  }

  additional_target_group_attachments = {
    app = {
      target_group_key = "app"
      target_id        = module.app_server.id
      port             = 80
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "load-balancing"
  })
}

# ── Compute: App Server ──

module "app_server" {
  source  = "app.terraform.io/hashi-demos-apj/ec2-instance/aws"
  version = "6.1.4"

  name                        = "${var.name_prefix}-${var.environment}-app"
  instance_type               = "t3.small"
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [module.ec2_sg.security_group_id]
  associate_public_ip_address = true
  create_security_group       = false

  user_data = <<-EOT
    #!/bin/bash
    dnf install -y httpd
    cat > /var/www/html/index.html <<'HTML'
    <h1>Uplift Demo</h1>
    <p>Environment: ${var.environment}</p>
    <p>Managed by Terraform via HCP Terraform</p>
    HTML
    systemctl start httpd
    systemctl enable httpd
  EOT

  tags = merge(local.common_tags, {
    Purpose = "application-server"
  })
}

# ── Storage: S3 Bucket ──

module "demo_bucket" {
  source  = "__MODULE_SOURCE__"
  version = "__MODULE_VERSION__"

  bucket_prefix = "${var.name_prefix}-${var.environment}"
  force_destroy = true

  attach_lb_log_delivery_policy = true

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "data-storage"
  })
}

# ── Data: DynamoDB Table ──

module "demo_metadata" {
  source  = "app.terraform.io/hashi-demos-apj/dynamodb-table/aws"
  version = "5.2.0"

  name     = "${var.name_prefix}-${var.environment}-metadata"
  hash_key = "id"

  attributes = [
    {
      name = "id"
      type = "S"
    }
  ]

  billing_mode                   = "PAY_PER_REQUEST"
  point_in_time_recovery_enabled = true
  server_side_encryption_enabled = true
  deletion_protection_enabled    = false

  tags = merge(local.common_tags, {
    Purpose = "metadata-tracking"
  })
}

# ── Messaging: SQS Queue ──

module "demo_events" {
  source  = "app.terraform.io/hashi-demos-apj/sqs/aws"
  version = "5.1.0"

  name                       = "${var.name_prefix}-${var.environment}-events"
  message_retention_seconds  = 345600
  visibility_timeout_seconds = 30
  sqs_managed_sse_enabled    = true

  create_dlq = true
  redrive_policy = {
    maxReceiveCount = 5
  }

  tags = merge(local.common_tags, {
    Purpose = "event-processing"
  })
}

# ── Notifications: SNS Topic ──

module "demo_alerts" {
  source  = "app.terraform.io/hashi-demos-apj/sns/aws"
  version = "7.0.0"

  name         = "${var.name_prefix}-${var.environment}-alerts"
  display_name = "Uplift Demo Alerts"

  tags = merge(local.common_tags, {
    Purpose = "operational-alerts"
  })
}

# ── Monitoring: CloudWatch Alarms ──

module "alb_5xx_alarm" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "5.7.2"

  alarm_name          = "${var.name_prefix}-${var.environment}-alb-5xx"
  alarm_description   = "ALB 5xx error rate exceeds threshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 10
  period              = 300
  statistic           = "Sum"

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_ELB_5XX_Count"

  dimensions = {
    LoadBalancer = module.alb.arn_suffix
  }

  alarm_actions = [module.demo_alerts.topic_arn]

  tags = merge(local.common_tags, {
    Purpose = "monitoring"
  })
}

module "sqs_depth_alarm" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "5.7.2"

  alarm_name          = "${var.name_prefix}-${var.environment}-sqs-depth"
  alarm_description   = "SQS queue depth exceeds threshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 100
  period              = 300
  statistic           = "Sum"

  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"

  dimensions = {
    QueueName = module.demo_events.queue_name
  }

  alarm_actions = [module.demo_alerts.topic_arn]

  tags = merge(local.common_tags, {
    Purpose = "monitoring"
  })
}
