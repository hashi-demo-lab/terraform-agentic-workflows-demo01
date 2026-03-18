# Look up existing VPC: by Name tag if vpc_name is provided, otherwise use default VPC
data "aws_vpc" "selected" {
  default = var.vpc_name == "" ? true : null

  dynamic "filter" {
    for_each = var.vpc_name != "" ? [var.vpc_name] : []
    content {
      name   = "tag:Name"
      values = [filter.value]
    }
  }
}

# Look up public subnets in the selected VPC (at least 2 AZs required for ALB)
# Uses map-public-ip-on-launch filter to reliably identify public subnets
# regardless of tagging conventions
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

# AWS account identity for Cloudability cost mapping
data "aws_caller_identity" "current" {}
