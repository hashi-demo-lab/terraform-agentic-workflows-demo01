# --------------------------------------------------------------------------
# Data Sources: existing VPC, public subnets, and caller identity
# --------------------------------------------------------------------------

# Look up existing VPC by Name tag, or fall back to default VPC
data "aws_vpc" "selected" {
  default = var.vpc_name == "" ? true : null

  tags = var.vpc_name != "" ? { Name = var.vpc_name } : null
}

# Discover public subnets in the selected VPC
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }

  tags = {
    Tier = var.subnet_tier_tag
  }
}

# Account identity for Cloudability org-specific pricing
data "aws_caller_identity" "current" {}
