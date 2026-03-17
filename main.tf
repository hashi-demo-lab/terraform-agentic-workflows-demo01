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
