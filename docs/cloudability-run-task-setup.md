# Cloudability Governance Run Task Setup Guide

Step-by-step guide for integrating IBM Cloudability Governance with HCP Terraform via Run Tasks to provide cost estimation, policy enforcement, and optimization recommendations in the plan-apply lifecycle.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **Cloudability subscription** | Premium or Standard with Governance entitlement (public preview since Nov 2025) |
| **HCP Terraform tier** | Plus or Enterprise (Run Tasks require paid tier) |
| **Terraform CLI** | v1.1.9+ |
| **Cloud provider** | AWS only (as of public preview) |
| **Network** | If TFE is behind a firewall, allow inbound from Cloudability IPs: `185.115.88.0/22`, `103.195.128.0/22`, `129.41.0.0/22` |

### Required Permissions

**Cloudability side:**

| Permission | Who Needs It |
|------------|-------------|
| `GovernanceFeatureConfigurationFullAccess` | Platform admin setting up the integration |
| `GovernanceFeaturePolicyFullAccess` | FinOps team creating policies |
| `GovernanceFeaturePRApproval` | Anyone who needs to override blocked runs |
| `GovernanceFeatureViewOnly` | Engineers viewing results (included in default user role) |

**HCP Terraform side:**

| Permission | Purpose |
|------------|---------|
| Manage Run Tasks | Create org-level run tasks |
| Manage Workspace Run Tasks | Attach run tasks to workspaces |

---

## Part 1: Cloudability Setup

### Step 1 — Install the IBM Cloudability GitHub App

Even when using the HCP Terraform Run Task path, the GitHub App is required for PR approval workflows.

1. Log into the Cloudability UI
2. Navigate to **Configuration > Integrations**
3. Install the IBM Cloudability GitHub App
4. Grant it access to the repositories that contain your Terraform code

> The app uses minimal, read-only permissions for PR metadata. It does **not** access your AWS environment.

### Step 2 — Generate Callback Credentials

1. In the Cloudability UI, go to **Configuration > Integrations**
2. Look for the **HCP Terraform / Terraform Enterprise** integration section
3. Generate a new credential pair:
   - **Callback URL** — the endpoint HCP Terraform will POST to after each plan
   - **HMAC Key** — shared secret for request authentication (SHA-512 HMAC)
4. **Save both values** — you'll need them when configuring the Run Task in HCP Terraform

### Step 3 — Create a Project

Projects group deployments and are the level at which governance policies are attached.

1. Navigate to **Configuration > Governance > Projects**
2. Create a new project (e.g., `platform-engineering`, `web-applications`)
3. Give it a meaningful name — this will appear in cost reports and dashboards

### Step 4 — Map Deployments to the Project

Each HCP Terraform workspace maps to a Cloudability **Deployment**. Deployments track all infrastructure changes (PRs/runs) for a given workspace.

1. In **Configuration > Governance > Deployments**, create deployments matching your workspace names
2. Assign each deployment to the project created in Step 3

> Deployments can also be auto-created on first run if using the GitHub Actions path.

### Step 5 — Create Governance Policies

Navigate to **Governance > Policies** and create policies in three categories:

#### Resource Policies
Control which cloud resources are allowed:

| Example Rule | Effect |
|-------------|--------|
| Block `m4.*` instance families | Engineers must use newer generation instances |
| Allow only `us-east-1`, `eu-west-1` regions | Restrict deployments to approved regions |
| Block `t2.large` and above | Force right-sized instances |

#### Tag Policies
Enforce required tagging:

| Example Rule | Effect |
|-------------|--------|
| Require `CostCenter` tag on all resources | Every resource must have cost attribution |
| Require `Environment` with values `dev`, `staging`, `prod` | Standardize environment naming |
| Require `Owner` tag | Ensure accountability |

#### Cost Guardrails
Set spending limits:

| Example Rule | Effect |
|-------------|--------|
| Monthly cost increase > $500 | Flag or block expensive changes |
| Total deployment cost > $5,000/month | Block over-budget deployments |

### Step 6 — Set Enforcement Mode

For each policy, choose the enforcement behavior:

| Mode | Behavior | When to Use |
|------|----------|-------------|
| **Inform** | Warns engineers but does NOT block the run | Rollout phase, non-critical environments |
| **Enforcement** | Blocks non-compliant runs; requires `GovernanceFeaturePRApproval` permission to override | Production workspaces, budget-critical projects |

> **Recommendation**: Start with **Inform** mode across all policies. Switch to **Enforcement** once teams are comfortable with the feedback loop.

### Step 7 — Configure Provider Account Mapping

Cloudability needs to know which AWS account each Terraform provider targets to look up your organization's negotiated pricing (not public list prices).

Add `aws_caller_identity` data sources to your Terraform code:

**Single account:**
```hcl
data "aws_caller_identity" "current" {}
```

**Multiple accounts (aliased providers):**
```hcl
data "aws_caller_identity" "production" {
  provider = aws.production
}

data "aws_caller_identity" "staging" {
  provider = aws.staging
}
```

This allows Cloudability to match resources to the correct account-specific pricing.

---

## Part 2: HCP Terraform Setup

### Step 8 — Create the Organization Run Task

**Option A — Via the UI:**

1. Sign into HCP Terraform
2. Go to **Settings > Integrations > Run Tasks**
3. Click **Create Run Task**
4. Fill in:

| Field | Value |
|-------|-------|
| Name | `cloudability-governance` |
| Endpoint URL | Callback URL from Step 2 |
| HMAC Key | HMAC Key from Step 2 |
| Enabled | `true` |

5. Click **Create**

**Option B — Via Terraform (recommended for IaC):**

```hcl
resource "tfe_organization_run_task" "cloudability" {
  organization = "my-org"
  name         = "cloudability-governance"
  url          = var.cloudability_callback_url
  hmac_key     = var.cloudability_hmac_key  # sensitive
  enabled      = true
  description  = "IBM Cloudability Governance - cost estimation and policy evaluation"
}
```

### Step 9 — Attach the Run Task to Workspaces

**Option A — Per-workspace (recommended for gradual rollout):**

Via UI:
1. Go to the target workspace > **Settings > Run Tasks**
2. Click **+** next to `cloudability-governance`
3. Set **Stage** to `Post-plan`
4. Set **Enforcement Level** to `Advisory` or `Mandatory`
5. Click **Create**

Via Terraform:
```hcl
resource "tfe_workspace_run_task" "cloudability_prod" {
  workspace_id      = tfe_workspace.prod.id
  task_id           = tfe_organization_run_task.cloudability.id
  enforcement_level = "mandatory"
  stages            = ["post_plan"]
}

resource "tfe_workspace_run_task" "cloudability_dev" {
  workspace_id      = tfe_workspace.dev.id
  task_id           = tfe_organization_run_task.cloudability.id
  enforcement_level = "advisory"
  stages            = ["post_plan"]
}
```

**Option B — Global (all workspaces):**

Requires the `global-run-task` organization entitlement.

```hcl
resource "tfe_organization_run_task_global_settings" "cloudability" {
  task_id           = tfe_organization_run_task.cloudability.id
  enabled           = true
  enforcement_level = "advisory"
  stages            = ["post_plan"]
}
```

### Understanding Run Stages

| Stage | When | Use For Cloudability? |
|-------|------|-----------------------|
| `pre_plan` | Before `terraform plan` | No — no plan data available |
| `post_plan` | After plan, before apply | **Yes — primary stage** |
| `pre_apply` | After confirmation, before apply | Optional secondary check |
| `post_apply` | After apply completes | Post-deployment audit only |

> **Always use `post_plan`** — this is where Cloudability evaluates the plan JSON for cost estimation, policy compliance, and recommendations.

---

## Part 3: Verification

### Step 10 — Trigger a Test Run

1. Queue a run in a workspace with the Run Task attached (push a commit, or manually trigger a plan)
2. After the plan completes, the run should pause at the **Run Tasks** stage
3. Check the HCP Terraform run UI — you should see `cloudability-governance` with a status:

| Status | Meaning |
|--------|---------|
| **Passed** | Plan complies with all policies |
| **Failed** | Policy violations detected (blocks apply if `mandatory`) |
| **Running** | Still processing |
| **Errored** | Integration failure (HMAC mismatch, timeout, network issue) |

### Step 11 — Verify in Cloudability

1. Open the Cloudability UI > **Governance** section
2. You should see the run with:
   - **Cost estimation** — monthly cost based on your org's negotiated pricing
   - **Policy evaluation** — pass/fail per policy
   - **Recommendations** — rightsizing and reserved instance suggestions

### Step 12 — Test a Known Violation

Create a deliberate policy violation to confirm end-to-end enforcement:

```hcl
# Example: use an instance type blocked by resource policy
resource "aws_instance" "test_violation" {
  ami           = "ami-0abcdef1234567890"
  instance_type = "m4.xlarge"  # blocked by policy

  # Deliberately omit required tags to trigger tag policy
}
```

Push this change and verify:
- The Run Task returns **Failed**
- The HCP Terraform UI shows the violation details
- If `mandatory`, the apply is blocked
- The Cloudability dashboard shows the violation in the project view

---

## Part 4: Terraform IaC — Complete Example

Manage the entire Run Task setup as code:

```hcl
terraform {
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.58"
    }
  }
}

provider "tfe" {
  hostname = "app.terraform.io"  # or your TFE hostname
}

# --- Variables ---

variable "cloudability_callback_url" {
  type        = string
  description = "Cloudability Governance callback URL"
}

variable "cloudability_hmac_key" {
  type        = string
  sensitive   = true
  description = "HMAC key for Run Task authentication"
}

variable "tfc_organization" {
  type        = string
  description = "HCP Terraform organization name"
}

variable "workspace_ids" {
  type        = map(string)
  description = "Map of workspace name to workspace ID for Run Task attachment"
  default     = {}
}

# --- Run Task ---

resource "tfe_organization_run_task" "cloudability" {
  organization = var.tfc_organization
  name         = "cloudability-governance"
  url          = var.cloudability_callback_url
  hmac_key     = var.cloudability_hmac_key
  enabled      = true
  description  = "IBM Cloudability Governance - cost and policy evaluation"
}

# --- Per-Workspace Attachment ---

resource "tfe_workspace_run_task" "cloudability" {
  for_each = var.workspace_ids

  workspace_id      = each.value
  task_id           = tfe_organization_run_task.cloudability.id
  enforcement_level = "advisory"  # start advisory, move to mandatory
  stages            = ["post_plan"]
}

# --- Outputs ---

output "run_task_id" {
  value       = tfe_organization_run_task.cloudability.id
  description = "Organization Run Task ID"
}

output "attached_workspaces" {
  value       = { for k, v in tfe_workspace_run_task.cloudability : k => v.id }
  description = "Workspace Run Task attachment IDs"
}
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Run Task shows "Errored" | HMAC key mismatch | Regenerate credentials in Cloudability; update in HCP Terraform |
| Run Task times out | Firewall blocking callbacks | Whitelist Cloudability IPs; ensure TFE allows inbound |
| No cost data returned | Missing `aws_caller_identity` data source | Add the data source for provider account mapping |
| Policies not evaluated | Deployment not mapped to a project | Create/assign deployment to a project in Cloudability |
| Cost estimate uses public pricing | Account not linked in Cloudability | Verify AWS account is onboarded in Cloudability with billing data |

---

## Querying Run Task Results via API

After a plan completes, retrieve cost results programmatically:

```bash
# 1. Get the run's task stages
curl -s \
  -H "Authorization: Bearer $TFC_TOKEN" \
  -H "Content-Type: application/vnd.api+json" \
  "https://app.terraform.io/api/v2/runs/${RUN_ID}/task-stages" \
  | jq '.data[] | select(.attributes.stage == "post_plan")'

# 2. Get the task result details (cost estimate, policy results)
curl -s \
  -H "Authorization: Bearer $TFC_TOKEN" \
  -H "Content-Type: application/vnd.api+json" \
  "https://app.terraform.io/api/v2/task-results/${TASK_RESULT_ID}" \
  | jq '.data.attributes | {status, message, url}'
```

This is how the SDD consumer workflow's `tf-consumer-validator` agent will consume cost feedback — by parsing `get_run_details` for task stage results between plan and apply.

---

## Security Notes

- Terraform plans are **never persisted** on Cloudability servers
- The GitHub App uses minimal, read-only permissions
- Cloudability does **not** access your AWS environment directly — it analyzes plan JSON only
- Pricing is determined via Cloudability's internal pricing service using your onboarded billing data
- HMAC authentication ensures only legitimate HCP Terraform callbacks are processed

---

## References

- [IBM Docs: Cloudability Governance — HCP Terraform/Terraform Enterprise](https://www.ibm.com/docs/en/cloudability-commercial/cloudability-premium/saas?topic=governance-hcp-terraformterraform-enterprise)
- [IBM Docs: Setup Cloudability Governance](https://www.ibm.com/docs/en/cloudability-commercial/cloudability-premium/saas?topic=preview-setup-cloudability-governance)
- [HashiCorp: Run Tasks Integration Docs](https://developer.hashicorp.com/terraform/cloud-docs/integrations/run-tasks)
- [HashiCorp: Run Tasks Workspace Settings](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/settings/run-tasks)
- [Terraform Registry: tfe_organization_run_task](https://registry.terraform.io/providers/hashicorp/tfe/latest/docs/resources/organization_run_task)
- [Terraform Registry: tfe_workspace_run_task](https://registry.terraform.io/providers/hashicorp/tfe/latest/docs/resources/workspace_run_task)
- [GitHub: IBM/ibm-cloudability-governance](https://github.com/IBM/ibm-cloudability-governance)
- [YouTube: Cost Management in Terraform with the Cloudability Run Task](https://www.youtube.com/watch?v=oc3Min8SGjE)
