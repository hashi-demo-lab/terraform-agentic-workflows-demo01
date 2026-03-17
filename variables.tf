variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "demo"
}

variable "project" {
  description = "Project name for resource tagging"
  type        = string
  default     = "consumer-uplift-demo"
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "ap-southeast-2"
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "uplift-demo"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
