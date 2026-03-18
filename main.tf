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
  # target_id will be wired to module.ec2_instance.id in Item C
  target_groups = {
    web = {
      name_prefix       = "web-"
      protocol          = "HTTP"
      port              = 80
      target_type       = "instance"
      create_attachment = false # EC2 instance attachment wired in Item C

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

# TODO: module.ec2_instance added in Item C

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

# TODO: module.dynamodb_table added in Item C

#--------------------------------------------------------------
# Messaging — SQS Queue
#--------------------------------------------------------------

# TODO: module.sqs added in Item C

#--------------------------------------------------------------
# Monitoring — SNS Topic, CloudWatch Alarms
#--------------------------------------------------------------

# TODO: module.sns, module.alb_5xx_alarm, module.sqs_depth_alarm added in Item D
