output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.alb.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer (primary application endpoint)"
  value       = module.alb.dns_name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = module.dynamodb.dynamodb_table_arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = module.dynamodb.dynamodb_table_id
}

output "ec2_instance_id" {
  description = "Instance ID of the web server"
  value       = module.ec2_web.id
}

output "ec2_public_ip" {
  description = "Public IP address of the web server"
  value       = module.ec2_web.public_ip
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for ALB access logs"
  value       = module.s3_alb_logs.s3_bucket_arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for ALB access logs"
  value       = module.s3_alb_logs.s3_bucket_name
}

output "sns_topic_arn" {
  description = "ARN of the SNS alerts topic"
  value       = module.sns_alerts.topic_arn
}

output "sqs_dlq_url" {
  description = "URL of the SQS dead-letter queue"
  value       = module.sqs.dead_letter_queue_url
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue"
  value       = module.sqs.queue_arn
}

output "sqs_queue_url" {
  description = "URL of the SQS queue"
  value       = module.sqs.queue_url
}

output "vpc_id" {
  description = "ID of the referenced VPC"
  value       = data.aws_vpc.selected.id
}
