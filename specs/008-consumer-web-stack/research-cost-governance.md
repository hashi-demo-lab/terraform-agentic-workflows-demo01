## Research: Cost governance configuration for the consumer web stack (dev environment)

### Decision

Use Cloudability Run Task in **advisory** mode for the dev workspace with cost allocation tags propagated via provider `default_tags`. No budget guardrail enforcement for dev -- inform-only mode provides visibility without blocking deployments. The `cba-workspace` private module exists but is a workspace provisioning module, not a cost policy module; cost governance is configured at the workspace level via `tfe_workspace_run_task` or the HCP Terraform UI.

### Modules Identified

- **Primary Module**: None -- cost governance is not a module-based concern. It is configured at the HCP Terraform workspace level.
- **Supporting Modules**:
  - `app.terraform.io/hashi-demos-apj/cba-workspace/tfe` v0.0.2 -- Workspace provisioning module (CBA prefix). Creates `tfe_workspace` resources. Does NOT manage run tasks or cost policies. Only relevant if provisioning the workspace itself via IaC.
  - `app.terraform.io/hashi-demos-apj/workspace/tfe` v0.0.2 -- General workspace provisioning module. Same shape as `cba-workspace`. Neither module exposes run task attachment inputs.
- **Glue Resources Needed**:
  - `data "aws_caller_identity" "current" {}` -- Required in consumer code for Cloudability to map resources to the correct AWS account and use organization-negotiated pricing instead of public list prices.
- **Wiring Considerations**: The `aws_caller_identity` data source requires no inputs and produces `account_id`, `arn`, and `user_id`. Cloudability reads this from the plan JSON automatically -- no explicit wiring to other modules is needed.

### Cost Estimate: Monthly Baseline (ap-southeast-2, Development)

All prices are AWS public on-demand pricing for `ap-southeast-2` (Sydney) as of March 2026. Cloudability will replace these with organization-negotiated rates if account mapping is configured.

| Service | Configuration | Estimated Monthly Cost | Notes |
|---------|--------------|----------------------|-------|
| **EC2 (t3.small)** | 1 instance, 2 vCPU, 2 GiB, on-demand | ~$19.34/mo | $0.0268/hr x 730 hrs. Consider Savings Plans if long-lived. |
| **ALB** | 1 ALB, minimal traffic | ~$22.63/mo | $0.031/hr fixed + $0.0084/LCU-hr. Dev traffic means ~0 LCU cost. |
| **S3** | Versioning enabled, ALB access logs, force destroy | ~$0.50-2.00/mo | $0.025/GB (first 50TB). ALB logs add ~1-5 GB/mo in dev. Versioning doubles storage for modified objects. |
| **DynamoDB** | PAY_PER_REQUEST, PITR, SSE | ~$0.25-1.00/mo | $1.4614/M write, $0.2923/M read (on-demand). PITR adds $0.000293/GB-hr. Dev usage is near-zero. |
| **SQS** | Standard queue + DLQ, managed SSE | ~$0.00-0.50/mo | First 1M requests/month free. $0.00044/request after. SSE via SQS-managed keys is free. |
| **SNS** | 1 topic, minimal notifications | ~$0.00/mo | First 1M publishes free. Email/HTTP endpoints free for delivery. |
| **CloudWatch** | 2 metric alarms (ALB 5xx, SQS depth) | ~$0.20/mo | $0.10/alarm/month (standard resolution). |
| **NAT Gateway** | None (public subnets only) | $0.00 | No NAT required -- all resources in public subnets. |
| **Data Transfer** | Minimal dev traffic | ~$0.50-2.00/mo | $0.114/GB outbound after first 100GB free tier. |
| **TOTAL ESTIMATE** | | **~$43-48/mo** | Conservative estimate for idle/minimal-traffic dev stack. |

### Cost Optimization Recommendations (Dev Environment)

1. **Instance sizing**: `t3.small` is appropriate for dev. Do NOT use `t3.micro` (insufficient memory for most web apps). The `t3.small` has burstable CPU with baseline credits sufficient for dev workloads.

2. **S3 lifecycle rules**: Not critical for dev, but consider adding a lifecycle rule to expire ALB access log objects after 30 days to prevent storage creep. The S3 module supports `lifecycle_rule` input.

3. **DynamoDB PAY_PER_REQUEST**: Correct choice for dev. Provisioned capacity would cost a minimum of ~$0.74/mo for 1 RCU + 1 WCU even when idle. On-demand is cheaper for sporadic dev usage.

4. **SQS managed SSE**: Free (uses SQS-owned keys). Do NOT switch to CMK-based SSE for dev -- adds $1/mo per key plus API call charges.

5. **ALB idle cost**: The ALB fixed hourly rate ($22.63/mo) is the largest fixed cost. If the dev environment is not needed 24/7, consider using a scheduled scale-down or destroy-and-recreate pattern. However, this adds operational complexity.

6. **EC2 stop/start**: For dev environments used only during business hours (10hr/day, weekdays), stopping the instance outside hours reduces EC2 cost from ~$19.34 to ~$5.77/mo. This is outside Terraform's scope (requires Lambda/EventBridge scheduler).

7. **No EBS optimization needed**: `t3.small` includes EBS-optimized by default. The root volume (gp3, 8GB default) costs ~$0.73/mo.

### Cost Allocation Tags

Per the consumer constitution (Section 3.3), provider `default_tags` MUST include these tags. The following tag set satisfies both the constitution and Cloudability tag policy requirements:

| Tag Key | Value | Purpose | Constitution Required |
|---------|-------|---------|----------------------|
| `ManagedBy` | `terraform` | Automation identification | Yes (Section 3.3) |
| `Environment` | `dev` | Environment classification, cost filtering | Yes (Section 3.3) |
| `Project` | `{var.project_name}` | Project-level cost attribution | Yes (Section 3.3) |
| `Owner` | `{var.owner}` | Accountability, cost allocation | Yes (Section 3.3) |
| `Application` | `{var.application_name}` | Application-level cost grouping | Yes (prompt requirement) |
| `CostCenter` | `{var.cost_center}` | FinOps cost allocation | Recommended by Cloudability |

**Note**: The `CostCenter` tag is recommended by Cloudability tag policies but is optional for dev environments. If the organization has a Cloudability tag policy requiring `CostCenter`, it should be added. The consumer code should make `cost_center` a variable with a sensible default (e.g., `"engineering"` or `"development"`).

### Cloudability Run Task Configuration

#### Organization Status

The `hashi-demos-apj` organization has 30 private modules but no dedicated cost governance module. The `cba-workspace` module (v0.0.2) is a workspace provisioning module, not a cost policy module. Run task configuration must be done at the workspace level.

#### Recommended Configuration for `sandbox_consumer_web_stack` Workspace

| Setting | Value | Rationale |
|---------|-------|-----------|
| Run Task Name | `cloudability-governance` | Standard name per setup guide |
| Stage | `post_plan` | Only stage where cost estimation is available |
| Enforcement Level | `advisory` | Dev environment -- inform, do not block |
| aws_caller_identity | Include in consumer code | Enables org-specific pricing |

#### Enforcement Mode Guidance

| Environment | Enforcement Level | Cloudability Policy Mode | Rationale |
|-------------|-------------------|------------------------|-----------|
| Development | `advisory` | Inform | Visibility without friction; devs iterate quickly |
| Staging | `advisory` | Inform | Mirror prod architecture but don't block |
| Production | `mandatory` | Enforcement | Budget protection; requires approval to override |

#### Setup Status Check

Before relying on Cloudability cost feedback, verify:

1. **Run Task exists at org level**: Check HCP Terraform > Settings > Integrations > Run Tasks for `cloudability-governance`
2. **Workspace attachment**: Check workspace > Settings > Run Tasks for the attachment
3. **Cloudability project mapping**: Ensure the workspace is mapped to a Cloudability Deployment under the correct Project
4. **Account mapping**: The `aws_caller_identity` data source must be in the Terraform code for org-specific pricing

If the Run Task is NOT yet configured at the org level, the consumer code should still include the `aws_caller_identity` data source (zero cost, no side effects) so that cost governance can be enabled later without code changes.

### Budget Guardrails

For a dev environment targeting ~$45/mo, the following Cloudability guardrails are recommended (if configuring policies):

| Policy Type | Rule | Mode | Threshold |
|-------------|------|------|-----------|
| Cost Guardrail | Monthly cost increase | Inform | > $100/change |
| Cost Guardrail | Total deployment cost | Inform | > $200/month |
| Resource Policy | Block large instances | Inform | > t3.medium |
| Tag Policy | Require Environment tag | Inform | Must be set |
| Tag Policy | Require CostCenter tag | Inform | Must be set |

These are informational only for dev. The actual policy creation happens in the Cloudability UI by a FinOps administrator, not in Terraform consumer code.

### Rationale

The dev stack estimated at ~$43-48/mo is modest. The ALB ($22.63) and EC2 ($19.34) dominate the cost. All other services (S3, DynamoDB, SQS, SNS, CloudWatch) are effectively free-tier or near-zero at dev traffic levels. Cloudability in advisory mode provides cost visibility without impeding development velocity. The `aws_caller_identity` data source should be included unconditionally -- it has zero cost and enables future cost governance activation.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Skip Cloudability entirely | Loses cost visibility; constitution Section 7.1 recommends cost estimation review |
| Mandatory enforcement for dev | Blocks deployments on cost policy violations; inappropriate for dev iteration speed |
| AWS Budgets via Terraform | Out of scope for consumer code (raw resource); would require a budget module not in private registry |
| Infracost as alternative to Cloudability | Organization uses Cloudability per established setup guide; no Infracost integration configured |
| Provisioned DynamoDB capacity | More expensive for idle dev workloads; PAY_PER_REQUEST is cheaper at low volume |
| t3.micro instead of t3.small | Insufficient memory (1 GiB) for most web applications; cost savings of ~$10/mo not worth reliability risk |

### Sources

- `/workspace/docs/cloudability-run-task-setup.md` -- Organization's Cloudability Run Task setup guide
- `/workspace/.foundations/memory/consumer-constitution.md` -- Consumer constitution Section 3.3 (Tagging), Section 5.1 (Validation Pipeline), Section 7.1 (Cost Optimization)
- HCP Terraform provider: `tfe_workspace_run_task` resource (providerDocID: 11596209) -- enforcement_level, stages configuration
- Private registry: `hashi-demos-apj` organization -- 30 modules inventoried, no dedicated cost governance module found
- AWS Pricing (ap-southeast-2, public on-demand, March 2026): EC2, ALB, S3, DynamoDB, SQS, SNS, CloudWatch
- IBM Docs: Cloudability Governance -- HCP Terraform/Terraform Enterprise integration
