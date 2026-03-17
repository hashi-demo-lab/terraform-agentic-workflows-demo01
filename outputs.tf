output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = null # TODO: wire to module.alb.arn in Item D
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer (primary application endpoint)"
  value       = null # TODO: wire to module.alb.dns_name in Item D
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = null # TODO: wire to module.dynamodb.dynamodb_table_arn in Item B
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = null # TODO: wire to module.dynamodb.dynamodb_table_id in Item B
}

output "ec2_instance_id" {
  description = "Instance ID of the web server"
  value       = null # TODO: wire to module.ec2_web.id in Item C
}

output "ec2_public_ip" {
  description = "Public IP address of the web server"
  value       = null # TODO: wire to module.ec2_web.public_ip in Item C
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for ALB access logs"
  value       = null # TODO: wire to module.s3_alb_logs.s3_bucket_arn in Item B
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for ALB access logs"
  value       = null # TODO: wire to module.s3_alb_logs.s3_bucket_name in Item B
}

output "sns_topic_arn" {
  description = "ARN of the SNS alerts topic"
  value       = null # TODO: wire to module.sns_alerts.topic_arn in Item B
}

output "sqs_dlq_url" {
  description = "URL of the SQS dead-letter queue"
  value       = null # TODO: wire to module.sqs.dead_letter_queue_url in Item B
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue"
  value       = null # TODO: wire to module.sqs.queue_arn in Item B
}

output "sqs_queue_url" {
  description = "URL of the SQS queue"
  value       = null # TODO: wire to module.sqs.queue_url in Item B
}

output "vpc_id" {
  description = "ID of the referenced VPC"
  value       = data.aws_vpc.selected.id
}
