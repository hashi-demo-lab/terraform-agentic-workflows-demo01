variable "alarm_sns_email" {
  description = "Email address to subscribe to the SNS alerts topic; no subscription created if empty"
  type        = string
  default     = ""

  validation {
    condition     = var.alarm_sns_email == "" || can(regex("^[^@]+@[^@]+\\.[^@]+$", var.alarm_sns_email))
    error_message = "Must be a valid email address or empty string."
  }
}

variable "application_name" {
  description = "Application name for tagging"
  type        = string
  default     = "web-stack"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,32}$", var.application_name))
    error_message = "Must be 1-32 characters, lowercase alphanumeric and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ap-southeast-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "Must be a valid AWS region identifier (e.g., ap-southeast-2)."
  }
}

variable "dynamodb_hash_key" {
  description = "DynamoDB table partition key attribute name"
  type        = string
  default     = "id"

  validation {
    condition     = length(var.dynamodb_hash_key) > 0
    error_message = "Must not be empty."
  }
}

variable "dynamodb_table_name" {
  description = "Suffix for the DynamoDB table name"
  type        = string
  default     = "app-data"

  validation {
    condition     = can(regex("^.{1,255}$", var.dynamodb_table_name))
    error_message = "Must be 1-255 characters."
  }
}

variable "environment" {
  description = "Environment name used for tagging and resource naming"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Must be one of: dev, staging, production."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the web server"
  type        = string
  default     = "t3.small"

  validation {
    condition     = can(regex("^t3a?\\.", var.instance_type))
    error_message = "Must be a valid t3 or t3a family type."
  }
}

variable "name_prefix" {
  description = "Resource naming prefix; if not provided, derived from project_name and environment"
  type        = string
  default     = null

  validation {
    condition     = var.name_prefix == null || can(regex("^[a-z0-9-]{1,24}$", var.name_prefix))
    error_message = "Must be 1-24 characters, lowercase alphanumeric and hyphens."
  }
}

variable "owner" {
  description = "Owner identifier for tagging (team or individual)"
  type        = string
  default     = "e2e-test"

  validation {
    condition     = length(var.owner) > 0
    error_message = "Must not be empty."
  }
}

variable "project_name" {
  description = "Project name used for tagging and resource naming prefix"
  type        = string
  default     = "web-stack"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,32}$", var.project_name))
    error_message = "Must be 1-32 characters, lowercase alphanumeric and hyphens."
  }
}

variable "sqs_max_receive_count" {
  description = "Maximum receive count before message is sent to DLQ"
  type        = number
  default     = 5

  validation {
    condition     = var.sqs_max_receive_count >= 1 && var.sqs_max_receive_count <= 1000
    error_message = "Must be between 1 and 1000."
  }
}

variable "sqs_message_retention_seconds" {
  description = "SQS message retention period in seconds (default 4 days)"
  type        = number
  default     = 345600

  validation {
    condition     = var.sqs_message_retention_seconds >= 60 && var.sqs_message_retention_seconds <= 1209600
    error_message = "Must be between 60 and 1209600."
  }
}

variable "sqs_visibility_timeout_seconds" {
  description = "SQS message visibility timeout in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.sqs_visibility_timeout_seconds >= 0 && var.sqs_visibility_timeout_seconds <= 43200
    error_message = "Must be between 0 and 43200."
  }
}

variable "subnet_tier_tag" {
  description = "Tag value used to filter public subnets (key: Tier)"
  type        = string
  default     = "Public"
}

variable "user_data" {
  description = "User data script for the EC2 instance bootstrap"
  type        = string
  default     = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Web Stack - Hello from $(hostname -f)</h1>" > /var/www/html/index.html
  EOF
}

variable "vpc_name" {
  description = "VPC Name tag to look up; if empty, uses the default VPC"
  type        = string
  default     = ""
}
