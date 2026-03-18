# Web Application Stack

Multi-tier web application infrastructure deployed on AWS via HCP Terraform, composed entirely from private registry modules.

## Architecture Overview

This deployment provisions the following components in AWS ap-southeast-2 (Sydney):

| Component | Module | Purpose |
|-----------|--------|---------|
| Application Load Balancer | `hashi-demos-apj/alb/aws` ~> 10.1 | Internet-facing HTTP load balancer with access logging |
| EC2 Instance | `hashi-demos-apj/ec2-instance/aws` ~> 6.1 | Single web server running Amazon Linux 2023 with httpd |
| Security Group | `hashi-demos-apj/security-group/aws` ~> 5.3 | EC2 security group: HTTP from VPC CIDR, all egress |
| S3 Bucket | `hashi-demos-apj/s3-bucket/aws` ~> 6.0 | ALB access logs with versioning and AES256 encryption |
| DynamoDB Table | `hashi-demos-apj/dynamodb-table/aws` ~> 5.2 | Application state with on-demand billing, PITR, SSE |
| SQS Queue | `hashi-demos-apj/sqs/aws` ~> 5.1 | Background message processing with dead-letter queue |
| SNS Topic | `hashi-demos-apj/sns/aws` ~> 7.0 | Operational alert routing |
| CloudWatch Alarms | `hashi-demos-apj/cloudwatch/aws` ~> 5.7 | ALB 5xx errors and SQS queue depth monitoring |

### Data Flow

```
Internet -> ALB (port 80) -> EC2 Instance (port 80)
                                 |
                            DynamoDB Table (application state)
                                 |
                            SQS Queue -> Dead-Letter Queue
                                 |
                            SNS Topic <- CloudWatch Alarms
```

## Prerequisites

1. **HCP Terraform workspace**: `sandbox_consumer_web_stack` in the `hashi-demos-apj` organization
2. **Dynamic credentials**: `agent_AWS_Dynamic_Creds` variable set providing AWS OIDC authentication
3. **Existing VPC**: A VPC with at least 2 public subnets tagged `Tier = public` across 2 availability zones (or a default VPC)
4. **Terraform CLI**: >= 1.14
5. **Private registry access**: Authenticated to `app.terraform.io/hashi-demos-apj`

## Usage

### 1. Configure variables

Copy the example variables file and set required values:

```bash
cp terraform.auto.tfvars.example terraform.auto.tfvars
```

Edit `terraform.auto.tfvars` to set the `owner` variable (required) and any optional overrides.

### 2. Initialize and plan

```bash
terraform init
terraform plan
```

### 3. Apply

```bash
terraform apply
```

### 4. Access the application

After apply completes, the ALB DNS name is available in the outputs:

```bash
terraform output alb_dns_name
```

### 5. Destroy

```bash
terraform destroy
```

All resources are configured for clean destruction (deletion protection disabled, force destroy enabled).

## Input Variables

| Variable | Type | Required | Default | Description |
|----------|------|:--------:|---------|-------------|
| `owner` | string | yes | -- | Resource owner for tagging and accountability |
| `aws_region` | string | no | `ap-southeast-2` | AWS region for all resources |
| `project_name` | string | no | `web-stack` | Project name used in resource naming and tags |
| `environment` | string | no | `dev` | Deployment environment (dev, staging, prod) |
| `application_name` | string | no | `web-app` | Application name for tagging |
| `instance_type` | string | no | `t3.small` | EC2 instance type (t2/t3 micro, small, or medium) |
| `vpc_name` | string | no | `""` | VPC Name tag to filter by; if empty, uses default VPC |
| `name_prefix` | string | no | `""` | Name prefix for resources; defaults to `{project_name}-{environment}` |
| `user_data` | string | no | (httpd script) | EC2 user data script for instance bootstrap |

## Outputs

| Output | Description |
|--------|-------------|
| `alb_dns_name` | DNS name of the application load balancer |
| `alb_arn` | ARN of the application load balancer |
| `ec2_instance_id` | EC2 instance ID |
| `ec2_public_ip` | EC2 instance public IP address |
| `s3_bucket_name` | S3 bucket name for ALB access logs |
| `s3_bucket_arn` | S3 bucket ARN |
| `dynamodb_table_name` | DynamoDB table name |
| `dynamodb_table_arn` | DynamoDB table ARN |
| `sqs_queue_url` | SQS queue URL |
| `sqs_queue_arn` | SQS queue ARN |
| `sqs_dlq_url` | SQS dead-letter queue URL |
| `sns_topic_arn` | SNS topic ARN for operational alerts |
| `vpc_id` | VPC ID used by the deployment |

## Cost Estimate

Estimated monthly cost for the dev environment: ~$43-48/month at on-demand pricing.

| Resource | Estimated Cost |
|----------|---------------|
| EC2 t3.small (on-demand) | ~$17/mo |
| ALB (fixed + LCU) | ~$18/mo |
| S3 (minimal storage) | < $1/mo |
| DynamoDB (on-demand, minimal) | < $1/mo |
| SQS (minimal usage) | < $1/mo |
| SNS (minimal usage) | < $1/mo |
| CloudWatch alarms (2x) | ~$0.20/mo |
| **Total** | **~$43-48/mo** |

Cloudability Run Task provides advisory cost governance on every plan.

## Security Controls

| Control | Status | Notes |
|---------|--------|-------|
| Encryption at rest (S3) | Enabled | AES256 server-side encryption |
| Encryption at rest (DynamoDB) | Enabled | Server-side encryption |
| Encryption at rest (SQS) | Enabled | SQS managed SSE |
| S3 public access | Blocked | All public access block defaults honoured |
| IMDSv2 enforcement | Enabled | Module default: `http_tokens = "required"` |
| ALB access logging | Enabled | Logs to S3 bucket with delivery policies |
| Provider authentication | Dynamic | HCP Terraform OIDC dynamic credentials |
| Resource tagging | Enforced | 5 default tags via provider `default_tags` |
| ALB deletion protection | Disabled | Dev environment override (NFR-7) |
| DynamoDB deletion protection | Disabled | Dev environment override (NFR-7) |
| EC2 public IP | Enabled | Dev environment override; SG limits to VPC CIDR |
| HTTPS/TLS | Not configured | Dev environment; no domain/certificate available |

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
