# Web Application Stack - Consumer Deployment

This deployment provisions a complete web application stack in the ap-southeast-2 (Sydney) region for a development environment. It composes networking, compute, storage, data, messaging, and monitoring infrastructure from private registry modules.

## Architecture

The stack references an existing VPC and discovers public subnets via data sources, then provisions:

- **Load Balancing**: Application Load Balancer with HTTP listener and target group
- **Compute**: Single EC2 instance (t3.small) running an HTTP application
- **Storage**: S3 bucket for ALB access logs with versioning and encryption
- **Data**: DynamoDB table with on-demand billing and point-in-time recovery
- **Messaging**: SQS queue with dead-letter queue and managed SSE
- **Monitoring**: SNS topic for alerts, CloudWatch alarms for ALB 5xx errors and SQS queue depth

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.14
- [HCP Terraform](https://app.terraform.io/) account with access to the `hashi-demos-apj` organization
- AWS dynamic credentials configured via HCP Terraform variable sets
- Existing VPC with public subnets tagged with `Tier = Public`

## Usage

1. Copy the example variable file and fill in required values:

   ```bash
   cp terraform.auto.tfvars.example terraform.auto.tfvars
   # Edit terraform.auto.tfvars with your values
   ```

2. Initialize Terraform (requires HCP Terraform authentication):

   ```bash
   terraform init
   ```

3. Review the plan:

   ```bash
   terraform plan
   ```

4. Apply the configuration:

   ```bash
   terraform apply
   ```

## Workspace Configuration

| Setting | Value |
|---------|-------|
| Organization | hashi-demos-apj |
| Workspace | sandbox_consumer_web_stack |
| Execution Mode | Remote |
| Variable Sets | AWS Dynamic Credentials |

## Security Notes

- All S3 public access is blocked (module secure defaults honoured)
- EC2 IMDSv2 is enforced (module secure default)
- SQS and DynamoDB encryption at rest enabled
- ALB access logging to S3 enabled
- HTTP-only listener is a documented `[SECURITY OVERRIDE]` for dev environment (HTTPS/TLS out of scope)
- Deletion protection disabled on ALB, DynamoDB, and S3 for dev teardown (`[SECURITY OVERRIDE]`)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.19 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.19 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_alb"></a> [alb](#module\_alb) | app.terraform.io/hashi-demos-apj/alb/aws | ~> 10.1 |
| <a name="module_alb_5xx_alarm"></a> [alb\_5xx\_alarm](#module\_alb\_5xx\_alarm) | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 |
| <a name="module_dynamodb"></a> [dynamodb](#module\_dynamodb) | app.terraform.io/hashi-demos-apj/dynamodb-table/aws | ~> 5.2 |
| <a name="module_ec2_sg"></a> [ec2\_sg](#module\_ec2\_sg) | app.terraform.io/hashi-demos-apj/security-group/aws | ~> 5.3 |
| <a name="module_ec2_web"></a> [ec2\_web](#module\_ec2\_web) | app.terraform.io/hashi-demos-apj/ec2-instance/aws | ~> 6.1 |
| <a name="module_s3_alb_logs"></a> [s3\_alb\_logs](#module\_s3\_alb\_logs) | app.terraform.io/hashi-demos-apj/s3-bucket/aws | ~> 6.0 |
| <a name="module_sns_alerts"></a> [sns\_alerts](#module\_sns\_alerts) | app.terraform.io/hashi-demos-apj/sns/aws | ~> 7.0 |
| <a name="module_sqs"></a> [sqs](#module\_sqs) | app.terraform.io/hashi-demos-apj/sqs/aws | ~> 5.1 |
| <a name="module_sqs_depth_alarm"></a> [sqs\_depth\_alarm](#module\_sqs\_depth\_alarm) | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 |

## Resources

| Name | Type |
|------|------|
| [random_id.suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_subnets.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets) | data source |
| [aws_vpc.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alarm_sns_email"></a> [alarm\_sns\_email](#input\_alarm\_sns\_email) | Email address to subscribe to the SNS alerts topic; no subscription created if empty | `string` | `""` | no |
| <a name="input_application_name"></a> [application\_name](#input\_application\_name) | Application name for tagging | `string` | `"web-stack"` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for deployment | `string` | `"ap-southeast-2"` | no |
| <a name="input_dynamodb_hash_key"></a> [dynamodb\_hash\_key](#input\_dynamodb\_hash\_key) | DynamoDB table partition key attribute name | `string` | `"id"` | no |
| <a name="input_dynamodb_table_name"></a> [dynamodb\_table\_name](#input\_dynamodb\_table\_name) | Suffix for the DynamoDB table name | `string` | `"app-data"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name used for tagging and resource naming | `string` | `"dev"` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type for the web server | `string` | `"t3.small"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Resource naming prefix; if not provided, derived from project\_name and environment | `string` | `null` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Owner identifier for tagging (team or individual) | `string` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project name used for tagging and resource naming prefix | `string` | n/a | yes |
| <a name="input_sqs_max_receive_count"></a> [sqs\_max\_receive\_count](#input\_sqs\_max\_receive\_count) | Maximum receive count before message is sent to DLQ | `number` | `5` | no |
| <a name="input_sqs_message_retention_seconds"></a> [sqs\_message\_retention\_seconds](#input\_sqs\_message\_retention\_seconds) | SQS message retention period in seconds (default 4 days) | `number` | `345600` | no |
| <a name="input_sqs_visibility_timeout_seconds"></a> [sqs\_visibility\_timeout\_seconds](#input\_sqs\_visibility\_timeout\_seconds) | SQS message visibility timeout in seconds | `number` | `30` | no |
| <a name="input_subnet_tier_tag"></a> [subnet\_tier\_tag](#input\_subnet\_tier\_tag) | Tag value used to filter public subnets (key: Tier) | `string` | `"Public"` | no |
| <a name="input_user_data"></a> [user\_data](#input\_user\_data) | User data script for the EC2 instance bootstrap | `string` | `"#!/bin/bash\nyum update -y\nyum install -y httpd\nsystemctl start httpd\nsystemctl enable httpd\necho \"<h1>Web Stack - Hello from $(hostname -f)</h1>\" > /var/www/html/index.html\n"` | no |
| <a name="input_vpc_name"></a> [vpc\_name](#input\_vpc\_name) | VPC Name tag to look up; if empty, uses the default VPC | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alb_arn"></a> [alb\_arn](#output\_alb\_arn) | ARN of the Application Load Balancer |
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | DNS name of the Application Load Balancer (primary application endpoint) |
| <a name="output_dynamodb_table_arn"></a> [dynamodb\_table\_arn](#output\_dynamodb\_table\_arn) | ARN of the DynamoDB table |
| <a name="output_dynamodb_table_name"></a> [dynamodb\_table\_name](#output\_dynamodb\_table\_name) | Name of the DynamoDB table |
| <a name="output_ec2_instance_id"></a> [ec2\_instance\_id](#output\_ec2\_instance\_id) | Instance ID of the web server |
| <a name="output_ec2_public_ip"></a> [ec2\_public\_ip](#output\_ec2\_public\_ip) | Public IP address of the web server |
| <a name="output_s3_bucket_arn"></a> [s3\_bucket\_arn](#output\_s3\_bucket\_arn) | ARN of the S3 bucket for ALB access logs |
| <a name="output_s3_bucket_name"></a> [s3\_bucket\_name](#output\_s3\_bucket\_name) | Name of the S3 bucket for ALB access logs |
| <a name="output_sns_topic_arn"></a> [sns\_topic\_arn](#output\_sns\_topic\_arn) | ARN of the SNS alerts topic |
| <a name="output_sqs_dlq_url"></a> [sqs\_dlq\_url](#output\_sqs\_dlq\_url) | URL of the SQS dead-letter queue |
| <a name="output_sqs_queue_arn"></a> [sqs\_queue\_arn](#output\_sqs\_queue\_arn) | ARN of the SQS queue |
| <a name="output_sqs_queue_url"></a> [sqs\_queue\_url](#output\_sqs\_queue\_url) | URL of the SQS queue |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the referenced VPC |
<!-- END_TF_DOCS -->
