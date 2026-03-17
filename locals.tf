locals {
  # Naming prefix: use explicit override or derive from project + environment
  name_prefix = var.name_prefix != null ? var.name_prefix : "${var.project_name}-${var.environment}"

  # Component names derived from the naming prefix
  alb_name            = "${local.name_prefix}-alb"
  ec2_name            = "${local.name_prefix}-web"
  ec2_sg_name         = "${local.name_prefix}-web-sg"
  log_bucket_name     = "${local.name_prefix}-alb-logs-${random_id.suffix.hex}"
  dynamodb_table_name = "${local.name_prefix}-${var.dynamodb_table_name}"
  sqs_queue_name      = "${local.name_prefix}-queue"
  sns_topic_name      = "${local.name_prefix}-alerts"

  # Common tags applied to module-level tags inputs
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}
