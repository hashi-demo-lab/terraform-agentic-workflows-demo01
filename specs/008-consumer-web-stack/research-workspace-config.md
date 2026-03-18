## Research: HCP Terraform Workspace Configuration for Consumer Web Stack

### Decision

Use the existing `hashi-demos-apj` organization and `sandbox` project (ID: `prj-QueMgU3LXgV2Ag7s`) with a new workspace `sandbox_consumer_web_stack` created via the HCP Terraform API before `terraform init`, configured for remote execution with dynamic AWS credentials from the `agent_AWS_Dynamic_Creds` variable set and Apptio-Cloudability run task for cost governance.

### Workspace Status

**Workspace `sandbox_consumer_web_stack` does NOT exist yet** -- confirmed via HCP Terraform API (HTTP 404). It must be created before running `terraform init`. The workspace creation pattern follows existing sandbox workspaces in the organization.

### Organization Details

| Setting | Value |
|---------|-------|
| Organization | `hashi-demos-apj` |
| Organization ID | `org-aptsDRkhPRfyGPKm` |
| Plan | `premium_internal` |
| Cost Estimation | Enabled (`cost-estimation-enabled: true`) |
| Default Execution Mode | `remote` |
| Stacks Enabled | Yes |

### Project Details

| Setting | Value |
|---------|-------|
| Project Name | `sandbox` |
| Project ID | `prj-QueMgU3LXgV2Ag7s` |
| Default Execution Mode | `remote` (inherited from org) |
| Current Workspace Count | 4 |
| Can Create Workspace | Yes (`can-create-workspace: true`) |

### Existing Workspace Patterns

All workspaces in the sandbox project follow these conventions:

| Workspace | TF Version | Execution Mode | VCS | Auto Apply |
|-----------|-----------|---------------|-----|-----------|
| `sandbox-consumer-asg-alb` | `1.14.6` | remote | None (CLI-driven) | false |
| `sandbox_sqsterraform-module-uplift` | `1.14.4` | remote | None (CLI-driven) | false |
| `terraform-agentic-workflows-demo01` | `~>1.14.0` | remote | None | -- |
| `aws-agentcore-claude-terraform-agent` | `1.14.6` | remote | None | -- |

**Pattern**: All sandbox workspaces use CLI-driven runs (no VCS connection), remote execution mode, and Terraform >= 1.14.x.

### Variable Sets

There is **one variable set** in the organization:

**`agent_AWS_Dynamic_Creds`** (ID: `varset-9BtXAvxByVGEnHWV`)

| Variable | Category | Value | Sensitive |
|----------|----------|-------|-----------|
| `TFC_AWS_PROVIDER_AUTH` | `env` | `true` | No |
| `TFC_AWS_RUN_ROLE_ARN` | `env` | `arn:aws:iam::855831148133:role/tfstacks-role` | No |
| `TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE` | `env` | `aws.workload.identity` | No |

- **Scope**: Applied to 2 projects (including `sandbox` / `prj-QueMgU3LXgV2Ag7s`)
- **Priority**: `true` (cannot be overridden by workspace variables)
- **Global**: `false` (project-scoped, not organization-wide)

This variable set enables **HCP Terraform Dynamic Provider Credentials** for AWS. When a run executes, HCP Terraform automatically:
1. Generates a short-lived OIDC token
2. Assumes the IAM role `arn:aws:iam::855831148133:role/tfstacks-role`
3. Injects temporary AWS credentials into the Terraform execution environment

**No static AWS credentials are needed in the workspace or provider configuration.**

### Run Tasks

| Run Task | Status | Stage | Enforcement | Scope |
|----------|--------|-------|-------------|-------|
| **Apptio-Cloudability** | Enabled, Global | `post_plan` | Advisory | Global (all workspaces) |
| HCP-Packer | Enabled, Not Global | -- | -- | Not attached to any workspace |
| security_vulnerabilities_checking (Snyk) | Enabled, Not Global | -- | -- | Not attached to any workspace |

**Apptio-Cloudability** is configured as a **global run task** with **advisory enforcement** -- it will run on every plan in every workspace but will NOT block applies. Cost estimates will appear in the run output.

### Policy Sets

**No Sentinel or OPA policy sets** are configured in the organization. Security enforcement relies on module secure defaults and run task advisory checks.

### Workspace Configuration for `sandbox_consumer_web_stack`

#### Recommended Settings

| Setting | Value | Rationale |
|---------|-------|-----------|
| Name | `sandbox_consumer_web_stack` | Matches consumer prompt specification |
| Organization | `hashi-demos-apj` | Target org |
| Project | `sandbox` (`prj-QueMgU3LXgV2Ag7s`) | Sandbox project for dev deployments |
| Execution Mode | `remote` | Matches org default and all sandbox workspaces |
| Terraform Version | `1.14.7` | Matches local CLI version; consistent with sandbox pattern |
| VCS Connection | None | CLI-driven workflow (matches all sandbox workspaces) |
| Auto Apply | `false` | Manual confirmation for safety (matches sandbox pattern) |
| Queue All Runs | `false` | No webhook-triggered runs (CLI-driven) |
| Allow Destroy Plan | `true` | Required for sandbox cleanup |
| Variable Sets | `agent_AWS_Dynamic_Creds` (inherited from project) | Dynamic AWS credentials |

#### Workspace Creation Script

The workspace must be created via API before `terraform init`:

```bash
TF_TOKEN="<token>"
curl -s \
  -H "Authorization: Bearer $TF_TOKEN" \
  -H "Content-Type: application/vnd.api+json" \
  -X POST "https://app.terraform.io/api/v2/organizations/hashi-demos-apj/workspaces" \
  -d '{
    "data": {
      "type": "workspaces",
      "attributes": {
        "name": "sandbox_consumer_web_stack",
        "terraform-version": "1.14.7",
        "auto-apply": false,
        "queue-all-runs": false,
        "allow-destroy-plan": true,
        "description": "Sandbox workspace for consumer web stack - ALB, EC2, S3, DynamoDB, SQS, SNS, CloudWatch"
      },
      "relationships": {
        "project": {
          "data": {
            "id": "prj-QueMgU3LXgV2Ag7s",
            "type": "projects"
          }
        }
      }
    }
  }'
```

### HCL Configuration Patterns

#### `backend.tf` -- Cloud Block

```hcl
terraform {
  cloud {
    organization = "hashi-demos-apj"

    workspaces {
      name = "sandbox_consumer_web_stack"
    }
  }
}
```

**Important**: The `cloud {}` block replaces the legacy `backend "remote" {}` block. It should be in `backend.tf` per the consumer constitution file structure.

#### `versions.tf` -- Terraform and Provider Constraints

```hcl
terraform {
  required_version = ">= 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.19"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
```

**Notes**:
- AWS provider `~> 6.19` is the minimum needed by several private registry modules (lock file shows `>= 6.19.0` constraint)
- The lock file already pins `hashicorp/aws` at `6.36.0` and `hashicorp/random` at `3.8.1`
- `required_version >= 1.14` matches the local CLI (1.14.7) and workspace pattern

#### `providers.tf` -- Provider Configuration

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Application = var.application_name
    }
  }

  # Dynamic credentials via HCP Terraform - no explicit credentials needed
  # The agent_AWS_Dynamic_Creds variable set handles authentication via:
  #   TFC_AWS_PROVIDER_AUTH = true
  #   TFC_AWS_RUN_ROLE_ARN = arn:aws:iam::855831148133:role/tfstacks-role
  #   TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE = aws.workload.identity
}
```

**Dynamic credentials flow**: HCP Terraform uses OIDC to assume the IAM role. No `access_key`, `secret_key`, or `assume_role` block is needed in the provider configuration. The `TFC_AWS_PROVIDER_AUTH=true` environment variable tells the AWS provider to use the dynamic credentials injected by HCP Terraform.

### Provider Credential Pattern Details

The `agent_AWS_Dynamic_Creds` variable set uses **HCP Terraform Workload Identity** (OIDC-based):

1. **`TFC_AWS_PROVIDER_AUTH = true`**: Enables dynamic credential injection for the AWS provider
2. **`TFC_AWS_RUN_ROLE_ARN`**: The IAM role that HCP Terraform assumes via OIDC federation
3. **`TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE`**: The OIDC audience value (`aws.workload.identity`)

The IAM role `arn:aws:iam::855831148133:role/tfstacks-role` must have:
- A trust policy allowing `app.terraform.io` as an OIDC identity provider
- IAM permissions sufficient for all resources the consumer web stack creates (EC2, ALB, S3, DynamoDB, SQS, SNS, CloudWatch, Security Groups)

### Wiring Considerations

- **`cloud {}` block goes in `backend.tf`** -- separate from `required_providers` in `versions.tf` per constitution
- **No workspace variables needed** -- dynamic credentials come from the project-scoped variable set; all other config comes from Terraform variables
- **Apptio-Cloudability run task** will automatically execute on every plan (global, advisory) -- no workspace-level configuration needed
- **No policy sets** to worry about -- compliance relies on module secure defaults
- **Workspace must be created before `terraform init`** -- the CLI-driven workflow requires the workspace to exist for the `cloud {}` block to connect

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| VCS-driven workflow | All sandbox workspaces use CLI-driven runs; VCS triggers not appropriate for dev/sandbox |
| Static AWS credentials | Constitution prohibits static credentials; dynamic credentials already configured via variable set |
| Local backend | Constitution requires `cloud {}` block for HCP Terraform |
| Workspace-level credential variables | Variable set already scoped to the sandbox project; duplicating credentials would violate DRY |
| Auto-apply enabled | Sandbox environment benefits from manual confirmation; matches existing workspace pattern |
| Separate `cloud {}` in `versions.tf` | Constitution specifies `backend.tf` for the cloud block |

### Sources

- HCP Terraform API: `GET /api/v2/organizations/hashi-demos-apj` (organization details)
- HCP Terraform API: `GET /api/v2/organizations/hashi-demos-apj/workspaces/sandbox_consumer_web_stack` (404 -- workspace does not exist)
- HCP Terraform API: `GET /api/v2/organizations/hashi-demos-apj/varsets` (variable set listing)
- HCP Terraform API: `GET /api/v2/varsets/varset-9BtXAvxByVGEnHWV?include=vars` (variable set details)
- HCP Terraform API: `GET /api/v2/organizations/hashi-demos-apj/projects` (project listing)
- HCP Terraform API: `GET /api/v2/organizations/hashi-demos-apj/tasks` (run tasks)
- HCP Terraform API: `GET /api/v2/organizations/hashi-demos-apj/policy-sets` (empty)
- HCP Terraform API: `GET /api/v2/organizations/hashi-demos-apj/workspaces?search=sandbox` (existing workspace patterns)
- Terraform provider docs: `hashicorp/tfe` v0.74.1 -- `tfe_workspace` resource, `tfe_variable_set` data source
- Consumer constitution: `.foundations/memory/consumer-constitution.md`
- Local environment: `terraform version` -> v1.14.7, lock file -> AWS provider 6.36.0
