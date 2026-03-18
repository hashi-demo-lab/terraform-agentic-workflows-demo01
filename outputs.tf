output "alb_dns_name" {
  description = "DNS name of the application load balancer"
  value       = "" # TODO: wire to module.alb.dns_name in Item B
}

output "alb_arn" {
  description = "ARN of the application load balancer"
  value       = "" # TODO: wire to module.alb.arn in Item B
}

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = "" # TODO: wire to module.ec2_instance.id in Item C
}

output "ec2_public_ip" {
  description = "EC2 instance public IP address"
  value       = "" # TODO: wire to module.ec2_instance.public_ip in Item C
}

output "s3_bucket_name" {
  description = "S3 bucket name for ALB access logs"
  value       = "" # TODO: wire to module.s3_bucket.s3_bucket_id in Item B
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = "" # TODO: wire to module.s3_bucket.s3_bucket_arn in Item B
}

output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = "" # TODO: wire to module.dynamodb_table.dynamodb_table_id in Item C
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN"
  value       = "" # TODO: wire to module.dynamodb_table.dynamodb_table_arn in Item C
}

output "sqs_queue_url" {
  description = "SQS queue URL"
  value       = "" # TODO: wire to module.sqs.queue_url in Item C
}

output "sqs_queue_arn" {
  description = "SQS queue ARN"
  value       = "" # TODO: wire to module.sqs.queue_arn in Item C
}

output "sqs_dlq_url" {
  description = "SQS dead-letter queue URL"
  value       = "" # TODO: wire to module.sqs.dead_letter_queue_url in Item C
}

output "sns_topic_arn" {
  description = "SNS topic ARN for operational alerts"
  value       = "" # TODO: wire to module.sns.topic_arn in Item D
}

output "vpc_id" {
  description = "VPC ID used by the deployment"
  value       = data.aws_vpc.selected.id
}
