output "alb_dns_name" {
  description = "DNS name of the application load balancer"
  value       = module.alb.dns_name
}

output "alb_arn" {
  description = "ARN of the application load balancer"
  value       = module.alb.arn
}

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = module.ec2_instance.id
}

output "ec2_public_ip" {
  description = "EC2 instance public IP address"
  value       = module.ec2_instance.public_ip
}

output "s3_bucket_name" {
  description = "S3 bucket name for ALB access logs"
  value       = module.s3_bucket.s3_bucket_name
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = module.s3_bucket.s3_bucket_arn
}

output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = module.dynamodb_table.dynamodb_table_id
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN"
  value       = module.dynamodb_table.dynamodb_table_arn
}

output "sqs_queue_url" {
  description = "SQS queue URL"
  value       = module.sqs.queue_url
}

output "sqs_queue_arn" {
  description = "SQS queue ARN"
  value       = module.sqs.queue_arn
}

output "sqs_dlq_url" {
  description = "SQS dead-letter queue URL"
  value       = module.sqs.dead_letter_queue_url
}

output "sns_topic_arn" {
  description = "SNS topic ARN for operational alerts"
  value       = "" # TODO: wire to module.sns.topic_arn in Item D
}

output "vpc_id" {
  description = "VPC ID used by the deployment"
  value       = data.aws_vpc.selected.id
}
