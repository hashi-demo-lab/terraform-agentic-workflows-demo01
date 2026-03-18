# ── Networking ──

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

# ── Compute ──

output "alb_dns_name" {
  description = "The DNS name of the ALB"
  value       = module.alb.dns_name
}

output "app_server_id" {
  description = "The EC2 instance ID"
  value       = module.app_server.id
}

output "app_server_public_ip" {
  description = "The public IP of the app server"
  value       = module.app_server.public_ip
}

# ── Storage ──

output "bucket_id" {
  description = "The name of the S3 bucket"
  value       = module.demo_bucket.s3_bucket_id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = module.demo_bucket.s3_bucket_arn
}

# ── Data ──

output "dynamodb_table_id" {
  description = "The ID of the DynamoDB metadata table"
  value       = module.demo_metadata.dynamodb_table_id
}

# ── Messaging ──

output "sqs_queue_url" {
  description = "The URL of the SQS event queue"
  value       = module.demo_events.queue_url
}

# ── Notifications ──

output "sns_topic_arn" {
  description = "The ARN of the SNS alerts topic"
  value       = module.demo_alerts.topic_arn
}
