variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-southeast-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "Region must be a valid AWS region format (e.g., ap-southeast-2)."
  }
}

variable "project_name" {
  description = "Project name used in resource naming and tags"
  type        = string
  default     = "web-stack"

  validation {
    condition     = length(var.project_name) >= 1 && length(var.project_name) <= 32
    error_message = "Project name must be between 1 and 32 characters."
  }
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "owner" {
  description = "Resource owner for tagging and accountability"
  type        = string
  default     = "platform-team"

  validation {
    condition     = length(var.owner) >= 1
    error_message = "Owner must be at least 1 character."
  }
}

variable "application_name" {
  description = "Application name for tagging"
  type        = string
  default     = "web-app"

  validation {
    condition     = length(var.application_name) >= 1 && length(var.application_name) <= 64
    error_message = "Application name must be between 1 and 64 characters."
  }
}

variable "name_prefix" {
  description = "Name prefix for resources; defaults to project_name-environment via locals if empty"
  type        = string
  default     = ""

  validation {
    condition     = length(var.name_prefix) <= 20
    error_message = "Name prefix must be 20 characters or fewer."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the web server"
  type        = string
  default     = "t3.small"

  validation {
    condition     = can(regex("^t[23]\\.(micro|small|medium)$", var.instance_type))
    error_message = "Instance type must match t2 or t3 micro, small, or medium (e.g., t3.small)."
  }
}

variable "vpc_name" {
  description = "VPC Name tag to filter by; if empty, uses default VPC"
  type        = string
  default     = ""
}

variable "user_data" {
  description = "EC2 user data script for instance bootstrap"
  type        = string
  default     = ""
}
