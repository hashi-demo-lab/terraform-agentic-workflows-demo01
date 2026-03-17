# Consumer: Web Application Stack with ALB, EC2, and Observability

**IMPORTANT** - Do not prompt me, make best practice decisions independently (this is for prompt eval)

Using the `/tf-consumer-e2e` workflow non-interactively.

## Infrastructure Requirements

Compose a web application stack from private registry modules using Terraform. The stack should include networking, compute, storage, messaging, and monitoring layers wired together.

### Networking

- Use an existing VPC and its public subnets via data source lookups (do NOT create a new VPC)
- Filter by tag `Name` or use the default VPC in the target region
- Expect at least 2 public subnets across 2 AZs

### Security

- Security group for EC2: allow HTTP (port 80) ingress from VPC CIDR, all egress

### Compute

- ALB in public subnets with HTTP listener on port 80
- Target group forwarding to a single EC2 instance on port 80
- Deletion protection disabled (dev environment)
- ALB access logs sent to the S3 bucket
- EC2 instance (`t3.small`) in the first public subnet with a simple HTTP user data script
- Associate public IP, use the security group above

### Storage

- S3 bucket with versioning, AES256 server-side encryption, and force destroy enabled
- Attach ELB and LB log delivery policies for ALB access logs

### Data

- DynamoDB table with a string hash key (`id`)
- PAY_PER_REQUEST billing, point-in-time recovery, server-side encryption
- Deletion protection disabled (dev environment)

### Messaging

- SQS queue with managed SSE, 4-day retention, 30s visibility timeout
- Dead-letter queue with max receive count of 5

### Notifications & Monitoring

- SNS topic for operational alerts
- CloudWatch metric alarm: ALB 5xx errors (threshold 10, 2 eval periods, 5 min)
- CloudWatch metric alarm: SQS queue depth (threshold 100, 2 eval periods, 5 min)
- Both alarms route to the SNS topic

### Cross-Cutting

- Common tags on all resources: `Environment`, `Project`, `ManagedBy` (`terraform`), `Application`
- Name prefix pattern: `{name_prefix}-{environment}`
- AWS Region: `ap-southeast-2`
- Environment: Development (minimal cost)

## HCP Terraform Configuration

- **Organization**: `hashi-demos-apj`
- **Project**: `sandbox`
- **Workspace**: `sandbox_consumer_web_stack`

## Workflow Instructions

- Compose infrastructure from private registry modules — do NOT write raw resources
- Wire data source outputs and module outputs to downstream module inputs (e.g., VPC ID to security group, subnet IDs to ALB)
- Follow best practice for module wiring and variable passthrough
- Use subagents to make best practice decisions if you need clarity
- Don't prompt the user - make decisions yourself
- If you hit issues, resolve them without prompting
- Auto-approve all design gates
