## Research: Cost Governance Patterns for Development Web Application Stack

### Decision

Use advisory-mode Cloudability Run Task with `aws_caller_identity` data source for org-specific pricing, enforce cost allocation tags via `default_tags`, disable deletion protection, and select minimal instance sizes across all resources -- targeting approximately $45-65/month for the dev stack in ap-southeast-2.

### Cloudability Run Task Integration

The organization has documented Cloudability Governance Run Task setup in `docs/cloudability-run-task-setup.md`. Key points:

- **Stage**: Run Task must be attached at `post_plan` stage -- this is where Cloudability evaluates plan JSON for cost estimation, policy compliance, and recommendations
- **Enforcement Levels**: Two modes available:
  - `advisory` -- warns engineers but does NOT block the run (recommended for dev)
  - `mandatory` -- blocks non-compliant runs; requires `GovernanceFeaturePRApproval` permission to override (recommended for production)
- **Provider Account Mapping**: Include `data "aws_caller_identity" "current" {}` in the consumer code so Cloudability uses the organization's negotiated pricing rather than public list prices
- **Policy Categories**: Resource policies (instance type restrictions), tag policies (required tags), and cost guardrails (spending limits)
- **HCP Terraform Requirement**: Run Tasks require Plus or Enterprise tier
- **Network**: If TFE is behind a firewall, allow inbound from Cloudability IPs: `185.115.88.0/22`, `103.195.128.0/22`, `129.41.0.0/22`
- **Terraform Config**: Workspace attachment via `tfe_workspace_run_task` resource with `enforcement_level = "advisory"` and `stages = ["post_plan"]`

### Cost Allocation Tags Requirements

Per the consumer constitution (Section 3.3), provider `default_tags` block MUST include:

| Tag Key | Required By | Purpose |
|---------|------------|---------|
| `ManagedBy` | Constitution | Must be `"terraform"` |
| `Environment` | Constitution + Cloudability | Environment classification (e.g., `dev`) |
| `Project` | Constitution | Project name for cost grouping |
| `Owner` | Constitution | Accountability and contact |
| `CostCenter` | Cloudability tag policy (recommended) | Cost attribution to business unit |

Additional recommended cost allocation tags:

| Tag Key | Purpose |
|---------|---------|
| `Application` | TFLint requirement; groups resources by application |
| `Purpose` | TFLint requirement; describes what the resource does |

These tags should be set in the provider `default_tags` block so they propagate to all resources automatically. Module-specific tags can be passed via each module's `tags` input for additional granularity.

### Cost-Effective Sizing for Dev Environment

#### EC2 Instance (Primary Compute)

| Setting | Dev Value | Rationale |
|---------|-----------|-----------|
| `instance_type` | `t3.small` (2 vCPU, 2 GiB) | Minimal viable size for web application; module defaults to `t3.micro` but `t3.small` specified in requirements |
| `monitoring` | `false` (basic monitoring) | Detailed monitoring adds $2.10/month; basic is sufficient for dev |
| `create_eip` | `false` | No need for static IP in dev; ALB provides the endpoint |
| `create_spot_instance` | `false` | Not recommended -- spot can be interrupted; not worth complexity for single dev instance |
| `ebs_optimized` | `null` (use default) | t3 instances are EBS-optimized by default at no extra cost |
| `root_block_device` | 20 GiB gp3 | Minimal root volume; gp3 is cheaper than gp2 with better performance |
| `disable_api_termination` | `false` | Dev instances should be easy to terminate; no termination protection needed |

**Monthly cost (ap-southeast-2)**: ~$19.20 (t3.small on-demand @ $0.026/hr x 730 hrs)

#### ALB (Application Load Balancer)

| Setting | Dev Value | Rationale |
|---------|-----------|-----------|
| `enable_deletion_protection` | `false` | **CRITICAL for dev** -- module defaults to `true`; must override for easy teardown |
| `internal` | `false` | External-facing for dev testing |
| `enable_http2` | `true` (default) | No cost impact |
| `drop_invalid_header_fields` | `true` (default) | Security feature, no cost impact |
| `access_logs` | `null` or disabled | S3 access log storage adds cost; skip for dev |

**Monthly cost (ap-southeast-2)**: ~$18.40 (ALB hourly @ $0.0252/hr x 730 hrs) + LCU charges (~$2-5 depending on traffic)

#### S3 Bucket

| Setting | Dev Value | Rationale |
|---------|-----------|-----------|
| `force_destroy` | `true` | **CRITICAL for dev** -- allows bucket deletion even with objects; essential for sandbox teardown |
| `versioning` | `{ enabled = false }` | No versioning in dev; reduces storage costs |
| `lifecycle_rule` | Expire objects after 30 days | Prevent unbounded storage growth |
| `server_side_encryption_configuration` | SSE-S3 (default) | Free encryption; do not use KMS unless required (KMS adds $1/month per key + API costs) |

**Monthly cost (ap-southeast-2)**: ~$0.50 (minimal storage, S3 Standard pricing $0.025/GB)

#### DynamoDB Table

| Setting | Dev Value | Rationale |
|---------|-----------|-----------|
| `billing_mode` | `PAY_PER_REQUEST` (module default) | On-demand pricing is ideal for dev with unpredictable/low traffic; no provisioned capacity to manage |
| `point_in_time_recovery_enabled` | `false` | No PITR in dev; saves ~20% of table storage cost |
| `deletion_protection_enabled` | `false` | Allow easy teardown for dev |
| `server_side_encryption_enabled` | `false` (module default) | Uses AWS-owned key by default (free); setting to `true` uses AWS-managed CMK ($1/month) |

**Monthly cost (ap-southeast-2)**: ~$1.25 (PAY_PER_REQUEST with minimal dev traffic; $1.25 per million write request units, $0.25 per million read request units)

#### SQS Queue

| Setting | Dev Value | Rationale |
|---------|-----------|-----------|
| `sqs_managed_sse_enabled` | `true` (module default) | SSE-SQS is free |
| `message_retention_seconds` | Default (345600 = 4 days) | Sufficient for dev |
| `create_dlq` | `false` | Skip DLQ in dev to reduce resource count |

**Monthly cost (ap-southeast-2)**: ~$0.00 (first 1M requests/month free; dev traffic negligible)

#### SNS Topic

| Setting | Dev Value | Rationale |
|---------|-----------|-----------|
| `kms_master_key_id` | `null` | No KMS encryption for dev; saves KMS key cost |
| `subscriptions` | Minimal | Only subscribe what is needed |

**Monthly cost (ap-southeast-2)**: ~$0.00 (first 1M publishes free; dev traffic negligible)

#### CloudWatch

| Setting | Dev Value | Rationale |
|---------|-----------|-----------|
| Log retention | 7 days | Minimal retention for dev; saves storage costs (default is often 30+ days) |
| Metric alarms | 1-2 basic alarms | First 10 alarms free; keep it minimal |
| Detailed monitoring | Disabled on EC2 | Basic monitoring (5-min intervals) is free |

**Monthly cost (ap-southeast-2)**: ~$2-5 (log ingestion + minimal custom metrics)

#### VPC (Supporting Infrastructure)

| Setting | Dev Value | Rationale |
|---------|-----------|-----------|
| NAT Gateway | Single NAT (not HA) | `enable_nat_gateway = true`, `single_nat_gateway = true` -- saves ~$65/month vs. per-AZ NAT |
| VPC Flow Logs | Disabled for dev | Each flow log destination adds cost; skip for dev |

**Monthly cost (ap-southeast-2)**: ~$34.50 (NAT Gateway @ $0.045/hr + $0.045/GB data processed)

### Expected Monthly Cost Estimate

| Resource | Estimated Monthly Cost (USD) | Notes |
|----------|------------------------------|-------|
| EC2 t3.small | $19.20 | On-demand, single instance |
| ALB | $20-23 | Hourly + minimal LCU |
| NAT Gateway | $34.50 | Single NAT gateway (dominant cost) |
| S3 Bucket | $0.50 | Minimal storage |
| DynamoDB (PAY_PER_REQUEST) | $1.25 | Minimal dev traffic |
| SQS | $0.00 | Free tier covers dev traffic |
| SNS | $0.00 | Free tier covers dev traffic |
| CloudWatch | $2-5 | Logs + basic alarms |
| EBS (20 GiB gp3) | $1.84 | $0.092/GB-month |
| **Total** | **~$80-85/month** | |

**Dominant cost driver**: NAT Gateway ($34.50/month) and ALB ($20-23/month) account for ~65% of total cost. If NAT Gateway can be avoided (e.g., public subnets only), total drops to ~$45-50/month.

### Cloudability Run Task Workspace Configuration

For the dev workspace, the Run Task should be configured as follows:

```hcl
# In workspace configuration (or via tfe_workspace_run_task)
enforcement_level = "advisory"   # Do NOT block dev deployments
stages            = ["post_plan"] # Evaluate after plan generation
```

**Advisory mode rationale for dev**:
1. Dev environments are experimental -- blocking deploys slows iteration
2. Engineers still see cost feedback in the run UI without being blocked
3. Cost guardrails can be set with higher thresholds for dev (e.g., monthly cost increase > $200)
4. Mandatory enforcement should be reserved for staging/production workspaces
5. The Cloudability setup guide recommends: "Start with Inform mode across all policies. Switch to Enforcement once teams are comfortable with the feedback loop."

### Recommended Cloudability Policies for Dev

| Policy Type | Rule | Mode | Rationale |
|------------|------|------|-----------|
| Resource | Block instances larger than `t3.medium` | Inform | Prevent accidental over-provisioning |
| Resource | Allow only `ap-southeast-2` region | Inform | Restrict to approved region |
| Tag | Require `Environment` tag | Inform | Cost allocation |
| Tag | Require `CostCenter` tag | Inform | Budget attribution |
| Cost Guardrail | Monthly cost increase > $200 | Inform | Flag expensive changes without blocking |

### Dev Environment Cost Optimization Best Practices

1. **Disable deletion protection on all resources** -- ALB (`enable_deletion_protection = false`), DynamoDB (`deletion_protection_enabled = false`), S3 (`force_destroy = true`) to enable clean sandbox teardown
2. **Single NAT Gateway** -- Use `single_nat_gateway = true` instead of per-AZ NATs; saves ~$70/month
3. **No PITR on DynamoDB** -- `point_in_time_recovery_enabled = false`; data is ephemeral in dev
4. **No versioning on S3** -- Dev buckets do not need object versioning
5. **Short log retention** -- 7-day CloudWatch log retention vs. 30+ days
6. **Basic monitoring** -- Skip detailed monitoring on EC2 ($2.10/month savings per instance)
7. **SSE-S3 over KMS** -- Use S3-managed encryption keys (free) instead of KMS ($1/month per key)
8. **SQS-managed SSE** -- `sqs_managed_sse_enabled = true` is free; no KMS needed
9. **PAY_PER_REQUEST for DynamoDB** -- Ideal for variable/low dev traffic; no capacity planning needed
10. **Skip access logging on ALB** -- Removes need for log-destination S3 bucket in dev
11. **Include `aws_caller_identity`** -- Enables org-specific pricing in Cloudability instead of public list prices
12. **Lifecycle rules on S3** -- Auto-expire objects after 30 days to prevent storage cost creep
13. **No EIP on EC2** -- Use ALB DNS name for access; saves $3.65/month per unused EIP

### Module-Specific Deletion Protection Overrides

These overrides weaken module defaults for dev environment cost efficiency and teardown ease. Per the consumer constitution, each requires a `[SECURITY OVERRIDE]` comment:

| Module | Default | Dev Override | Comment Required |
|--------|---------|-------------|------------------|
| ALB | `enable_deletion_protection = true` | `false` | `[SECURITY OVERRIDE] Dev environment: deletion protection disabled for easy teardown` |
| DynamoDB | `deletion_protection_enabled = null` | `false` (explicit) | Optional -- default is already permissive |
| S3 | `force_destroy = false` | `true` | `[SECURITY OVERRIDE] Dev environment: force_destroy enabled for sandbox cleanup` |

### Rationale

All cost optimization recommendations are based on the principle that dev environments should minimize spend while maintaining functional parity with production architecture. The Cloudability Run Task in advisory mode provides cost visibility without impeding development velocity. The dominant cost drivers (NAT Gateway and ALB) are inherent to the architecture and cannot be optimized further without changing the network topology. Total estimated cost of $80-85/month is reasonable for a full-featured dev web stack.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Mandatory Cloudability enforcement for dev | Slows development iteration; setup guide recommends starting with Inform/Advisory mode |
| Spot instances for EC2 | Risk of interruption outweighs ~60% cost savings for a single dev instance |
| VPC endpoints instead of NAT Gateway | More complex setup; NAT is simpler for dev and supports all AWS services |
| Provisioned DynamoDB capacity | Requires capacity planning; PAY_PER_REQUEST is simpler and cheaper at dev traffic levels |
| KMS encryption everywhere | Adds $1/month per key with no security benefit over SSE-S3/SSE-SQS for dev data |
| Skip Cloudability entirely for dev | Loses cost visibility; even advisory mode provides valuable feedback to engineers |
| No NAT Gateway (public subnets only) | Would save $34.50/month but breaks production architecture parity and security posture |

### Sources

- `docs/cloudability-run-task-setup.md` -- Organization Cloudability Governance Run Task setup guide
- `.foundations/memory/consumer-constitution.md` -- Consumer constitution (Sections 3.3, 7.1, 7.3)
- Private registry module details: `hashi-demos-apj/ec2-instance/aws` v6.1.4, `hashi-demos-apj/alb/aws` v10.1.0, `hashi-demos-apj/s3-bucket/aws` v6.0.0, `hashi-demos-apj/dynamodb-table/aws` v5.2.0, `hashi-demos-apj/sqs/aws` v5.1.0, `hashi-demos-apj/sns/aws` v7.0.0, `hashi-demos-apj/cloudwatch/aws` v5.7.2, `hashi-demos-apj/vpc/aws` v6.5.0
- AWS ap-southeast-2 pricing (as of March 2026): [EC2](https://aws.amazon.com/ec2/pricing/on-demand/), [ALB](https://aws.amazon.com/elasticloadbalancing/pricing/), [NAT Gateway](https://aws.amazon.com/vpc/pricing/), [S3](https://aws.amazon.com/s3/pricing/), [DynamoDB](https://aws.amazon.com/dynamodb/pricing/)
- [IBM Docs: Cloudability Governance](https://www.ibm.com/docs/en/cloudability-commercial/cloudability-premium/saas?topic=governance-hcp-terraformterraform-enterprise)
- [HashiCorp: Run Tasks Integration](https://developer.hashicorp.com/terraform/cloud-docs/integrations/run-tasks)
