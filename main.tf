#--------------------------------------------------------------
# Glue Resources
#--------------------------------------------------------------

resource "random_string" "suffix" {
  length  = 8
  lower   = true
  upper   = false
  special = false
}

#--------------------------------------------------------------
# Networking — ALB, Security Groups
#--------------------------------------------------------------

# EC2 security group: HTTP ingress from VPC CIDR, all egress
module "ec2_sg" {
  source  = "app.terraform.io/hashi-demos-apj/security-group/aws"
  version = "~> 5.3"

  name        = "${local.name_prefix}-ec2-sg"
  description = "Security group for EC2 web server -- HTTP from VPC CIDR"
  vpc_id      = local.vpc_id

  # Ingress: HTTP port 80 from VPC CIDR only
  ingress_with_cidr_blocks = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "HTTP from VPC CIDR"
      cidr_blocks = local.vpc_cidr_block
    }
  ]

  # Egress: all traffic to anywhere
  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "All egress"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  tags = {
    Component = "networking"
  }
}

# Application Load Balancer with HTTP listener, target group, and access logging
module "alb" {
  source  = "app.terraform.io/hashi-demos-apj/alb/aws"
  version = "~> 10.1"

  name               = "${local.name_prefix}-alb"
  load_balancer_type = "application"
  vpc_id             = local.vpc_id
  subnets            = local.public_subnets

  # [SECURITY OVERRIDE] Deletion protection disabled -- dev/sandbox environment
  # must be fully destroyable without manual intervention (NFR-7)
  enable_deletion_protection = false

  # Access logging to S3 bucket
  access_logs = {
    bucket  = module.s3_bucket.s3_bucket_name
    enabled = true
    prefix  = "alb"
  }

  # ALB-managed security group: HTTP from internet, all egress
  create_security_group = true

  security_group_ingress_rules = {
    http = {
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
      cidr_ipv4   = "0.0.0.0/0"
      description = "All egress"
    }
  }

  # HTTP listener on port 80, forwarding to the web target group
  # [SECURITY OVERRIDE] HTTP listener without TLS -- dev environment,
  # no sensitive data in transit, no domain/certificate available
  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"

      forward = {
        target_group_key = "web"
      }
    }
  }

  # Target group for EC2 instances on port 80
  # Wiring: module.ec2_instance.id -> target_groups.web.target_id
  target_groups = {
    web = {
      name_prefix       = "web-"
      protocol          = "HTTP"
      port              = 80
      target_type       = "instance"
      target_id         = module.ec2_instance.id
      create_attachment = true

      health_check = {
        enabled             = true
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        interval            = 30
        timeout             = 5
      }
    }
  }

  tags = {
    Component = "networking"
  }
}

#--------------------------------------------------------------
# Compute — EC2 Instance
#--------------------------------------------------------------

# EC2 web server instance: Amazon Linux 2023, first public subnet, HTTP via security group
# AMI lookup via module default SSM parameter: /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64
module "ec2_instance" {
  source  = "app.terraform.io/hashi-demos-apj/ec2-instance/aws"
  version = "~> 6.1"

  name          = "${local.name_prefix}-web"
  instance_type = var.instance_type

  # Networking: first public subnet, security group from ec2_sg module
  # Wiring: data.aws_subnets.public.ids[0] -> subnet_id
  # Wiring: module.ec2_sg.security_group_id -> vpc_security_group_ids (wrapped in list)
  subnet_id              = local.public_subnets[0]
  vpc_security_group_ids = [module.ec2_sg.security_group_id]

  # [SECURITY OVERRIDE] Public IP enabled -- dev environment requires direct HTTP access;
  # ALB in public subnets requires reachable targets. SG limits ingress to VPC CIDR on port 80.
  associate_public_ip_address = true

  # User data: httpd install script (resolved via locals)
  user_data = local.user_data

  # Disable module-created security group; using standalone ec2_sg module instead
  create_security_group = false

  # IMDSv2 enforcement: module defaults http_tokens = "required", hop_limit = 1 (honoured)

  # Root EBS volume encryption
  root_block_device = {
    encrypted = true
    type      = "gp3"
    size      = 20
  }

  tags = {
    Component = "compute"
  }
}

#--------------------------------------------------------------
# Storage — S3 Bucket
#--------------------------------------------------------------

# S3 bucket for ALB access logs with versioning, encryption, and log delivery policies
module "s3_bucket" {
  source  = "app.terraform.io/hashi-demos-apj/s3-bucket/aws"
  version = "~> 6.0"

  bucket      = "${local.name_prefix}-alb-logs-${random_string.suffix.result}"
  environment = var.environment

  # Versioning enabled for audit trail
  versioning = {
    enabled = true
  }

  # AES256 server-side encryption (service-managed keys)
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  # Force destroy for dev environment (NFR-7)
  force_destroy = true

  # Bucket policies for ALB log delivery
  attach_elb_log_delivery_policy = true
  attach_lb_log_delivery_policy  = true

  tags = {
    Component = "storage"
    Purpose   = "ALB access logs"
  }
}

#--------------------------------------------------------------
# Data — DynamoDB Table
#--------------------------------------------------------------

# DynamoDB table for application state: on-demand billing, PITR, SSE enabled
module "dynamodb_table" {
  source  = "app.terraform.io/hashi-demos-apj/dynamodb-table/aws"
  version = "~> 5.2"

  name     = "${local.name_prefix}-data"
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

  # [SECURITY OVERRIDE] Deletion protection disabled -- dev/sandbox environment
  # must be fully destroyable without manual intervention (NFR-7)
  deletion_protection_enabled = false

  tags = {
    Component = "data"
  }
}

#--------------------------------------------------------------
# Messaging — SQS Queue
#--------------------------------------------------------------

# SQS queue with DLQ for background message processing
module "sqs" {
  source  = "app.terraform.io/hashi-demos-apj/sqs/aws"
  version = "~> 5.1"

  name                       = "${local.name_prefix}-queue"
  message_retention_seconds  = 345600 # 4 days
  visibility_timeout_seconds = 30
  sqs_managed_sse_enabled    = true

  # Dead-letter queue: module auto-wires redrive policy with maxReceiveCount = 5
  create_dlq = true

  tags = {
    Component = "messaging"
  }
}

#--------------------------------------------------------------
# Monitoring — SNS Topic, CloudWatch Alarms
#--------------------------------------------------------------

# SNS topic for operational alert routing
module "sns" {
  source  = "app.terraform.io/hashi-demos-apj/sns/aws"
  version = "~> 7.0"

  name = "${local.name_prefix}-alerts"

  tags = {
    Component = "monitoring"
  }
}

# CloudWatch alarm: ALB 5xx error rate exceeds threshold
# Wiring: module.alb.arn_suffix -> dimensions.LoadBalancer
# Wiring: module.sns.topic_arn -> alarm_actions, ok_actions (wrapped in list)
module "alb_5xx_alarm" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.7"

  alarm_name          = "${local.name_prefix}-alb-5xx"
  alarm_description   = "ALB 5xx error rate exceeds threshold"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 10
  period              = 300
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = module.alb.arn_suffix
  }

  alarm_actions = [module.sns.topic_arn]
  ok_actions    = [module.sns.topic_arn]

  tags = {
    Component = "monitoring"
  }
}

# CloudWatch alarm: SQS queue depth exceeds threshold
# Wiring: module.sqs.queue_name -> dimensions.QueueName
# Wiring: module.sns.topic_arn -> alarm_actions, ok_actions (wrapped in list)
module "sqs_depth_alarm" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.7"

  alarm_name          = "${local.name_prefix}-sqs-depth"
  alarm_description   = "SQS queue depth exceeds threshold"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Average"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 100
  period              = 300
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = module.sqs.queue_name
  }

  alarm_actions = [module.sns.topic_arn]
  ok_actions    = [module.sns.topic_arn]

  tags = {
    Component = "monitoring"
  }
}
