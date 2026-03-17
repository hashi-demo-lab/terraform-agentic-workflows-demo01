## Research: HCP Terraform Workspace Configuration for Consumer Web Stack

### Decision

Use the `cloud {}` block in `versions.tf` targeting the `hashi-demos-apj` organization and `sandbox_consumer_web_stack` workspace, with dynamic provider credentials for AWS authentication and `default_tags` for consistent tagging -- this follows the consumer constitution pattern and avoids static credentials entirely.

### Workspace Existence

The workspace `sandbox_consumer_web_stack` must be created in HCP Terraform before `terraform init` can succeed. The `cloud {}` block references the workspace by name -- if it does not exist, `terraform init` will fail with a workspace-not-found error.

**Pre-deployment steps** (manual or via TFE provider in a bootstrap workspace):
1. Create workspace `sandbox_consumer_web_stack` in the `hashi-demos-apj` organization
2. Assign it to the `sandbox` project
3. Set execution mode to `Remote`
4. Pin Terraform version to `>= 1.14`
5. Configure dynamic provider credentials for AWS (see section below)

Workspace can be checked via the TFE API or `tfe_workspace` data source:
```hcl
data "tfe_workspace" "this" {
  name         = "sandbox_consumer_web_stack"
  organization = "hashi-demos-apj"
}
```

### Cloud Block Configuration

Per the consumer constitution (Section 4.1), the `cloud {}` block goes inside the `terraform {}` block in `versions.tf`. This replaces any legacy `backend` block.

```hcl
terraform {
  required_version = ">= 1.14"

  cloud {
    organization = "hashi-demos-apj"

    workspaces {
      name = "sandbox_consumer_web_stack"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

**Key points:**
- The `cloud {}` block and `backend {}` block are mutually exclusive -- you cannot use both
- The `cloud {}` block does NOT support variable interpolation -- organization and workspace names must be literal strings
- The workspace name in the `cloud {}` block must match an existing workspace in HCP Terraform
- `required_version = ">= 1.14"` ensures compatibility with the latest Terraform features
- Provider version `~> 5.0` uses pessimistic constraint per constitution requirement. Note: if any private registry modules require AWS provider >= 6.x (e.g., the SNS module per project MEMORY.md), this must be bumped to `~> 6.0`
- There is no `project` attribute in the `cloud {}` block -- the workspace must already be assigned to the `sandbox` project in HCP Terraform

### Dynamic Provider Credentials Setup

Dynamic provider credentials eliminate static AWS access keys. HCP Terraform generates short-lived credentials for each run using OIDC federation with AWS IAM.

**How it works:**
1. HCP Terraform acts as an OIDC identity provider for an AWS IAM role
2. Before each run, HCP Terraform exchanges its OIDC token for temporary AWS credentials
3. The AWS provider automatically picks up the credentials via environment variables injected by HCP Terraform

**Workspace-level environment variables required** (set in HCP Terraform, NOT in code):

| Variable | Category | Value | Sensitive |
|----------|----------|-------|-----------|
| `TFC_AWS_PROVIDER_AUTH` | env | `true` | No |
| `TFC_AWS_RUN_ROLE_ARN` | env | `arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>` | No |

**AWS-side prerequisites:**
- An IAM OIDC provider configured for `app.terraform.io`
- An IAM role with a trust policy allowing `app.terraform.io` as the federated principal
- The trust policy should scope access to the specific organization and workspace:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/app.terraform.io"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "app.terraform.io:aud": "aws.workload.identity"
        },
        "StringLike": {
          "app.terraform.io:sub": "organization:hashi-demos-apj:project:sandbox:workspace:sandbox_consumer_web_stack:run_phase:*"
        }
      }
    }
  ]
}
```

**Provider configuration in code** (no credentials in HCL):
```hcl
provider "aws" {
  region = var.aws_region
  # Dynamic credentials injected by HCP Terraform -- no access_key/secret_key
}
```

When dynamic credentials are configured, the AWS provider picks them up automatically via environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) that HCP Terraform injects at run time.

### Provider Configuration with default_tags

Per the consumer constitution (Section 3.3), provider `default_tags` MUST include `ManagedBy`, `Environment`, `Project`, and `Owner`. The web stack prompt also requires `Application`.

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Application = var.application_name
    }
  }
}
```

**Important considerations:**
- `default_tags` propagate to ALL resources managed by this provider instance
- Resources can override individual tags via their own `tags` argument
- `tags_all` attribute on resources shows the merged result of `default_tags` + resource-level `tags`
- `aws_autoscaling_group` is the one exception -- it does NOT inherit `default_tags`
- Tags can also be supplied via the `TF_AWS_DEFAULT_TAGS_<key>=<value>` environment variable pattern
- For cost allocation, `Environment` and `Project` tags serve as the primary allocation dimensions

### Variable Sets

Variable sets in HCP Terraform provide shared configuration across workspaces. For this deployment, the following variable sets are relevant:

**Expected variable sets in `hashi-demos-apj`:**

| Variable Set | Scope | Purpose | Key Variables |
|-------------|-------|---------|---------------|
| AWS Dynamic Credentials | Project or workspace | OIDC auth for AWS | `TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN` |
| Common Tags | Organization-wide (global) | Standard tagging | Could supply `TF_AWS_DEFAULT_TAGS_*` env vars |

**How to verify available variable sets:**
- HCP Terraform UI: Settings > Variable Sets in the `hashi-demos-apj` organization
- TFE data source: `data "tfe_variable_set" { name = "<name>"; organization = "hashi-demos-apj" }`
- TFE API: `GET /api/v2/organizations/hashi-demos-apj/varsets`

**Variable set attachment:**
- Global variable sets apply to all workspaces automatically
- Project-scoped variable sets apply to all workspaces in the project
- Workspace-scoped variable sets must be explicitly attached via `tfe_workspace_variable_set`

**Priority variable sets** (TFE provider v0.74+) cannot be overridden by workspace-level variables -- useful for enforcing organization-wide settings.

### Required Workspace Variables

These are the Terraform variables the consumer code expects, which must be set either in HCP Terraform workspace variables, variable sets, or `*.tfvars` files:

| Variable | Category | Required | Default in Code | Set Via | Description |
|----------|----------|----------|----------------|---------|-------------|
| `aws_region` | terraform | Yes | `"ap-southeast-2"` | Code default | AWS deployment region |
| `environment` | terraform | Yes | `"dev"` | Code default | Environment name for tagging and naming |
| `project_name` | terraform | Yes | -- | Workspace variable | Project name for tagging |
| `application_name` | terraform | Yes | -- | Workspace variable | Application name for tagging |
| `name_prefix` | terraform | Yes | -- | Workspace variable | Resource naming prefix |
| `TFC_AWS_PROVIDER_AUTH` | env | Yes | -- | Variable set | Enables dynamic credentials |
| `TFC_AWS_RUN_ROLE_ARN` | env | Yes | -- | Variable set | IAM role ARN for OIDC auth |

**Environment variables (set in workspace, NOT in code):**
- `TFC_AWS_PROVIDER_AUTH=true` -- enables the dynamic credentials workflow
- `TFC_AWS_RUN_ROLE_ARN=arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>` -- the IAM role to assume

### Backend Configuration Best Practices

1. **Use `cloud {}` not `backend "remote"`**: The `cloud {}` block is the modern replacement. The `backend "remote"` block is legacy and lacks project support.

2. **No `backend.tf` separation needed**: The consumer constitution template shows `cloud {}` inside `versions.tf` in the `terraform {}` block. A separate `backend.tf` is technically supported but creates confusion -- the `cloud {}` block must be in the `terraform {}` block alongside `required_providers`.

3. **Workspace naming convention**: `sandbox_consumer_web_stack` follows the pattern `{project}_{feature}` which is clear and sortable.

4. **State management**: HCP Terraform handles state locking, versioning, and encryption automatically. No additional S3 backend or DynamoDB lock table is needed.

5. **Local overrides for development**: Developers can use `terraform login` to authenticate locally. The `cloud {}` block works for both local CLI-driven runs and remote execution.

6. **Override file for local development**: When testing locally without HCP Terraform, use `override.tf` (gitignored) to replace the cloud block:
   ```hcl
   # override.tf (gitignored -- local development only)
   terraform {
     cloud {}  # empty cloud block disables remote backend
   }
   ```
   Or use `TF_WORKSPACE` environment variable and `-backend=false` for plan-only validation.

### Terraform Version Constraints

- `required_version = ">= 1.14"` ensures the latest language features are available
- Terraform 1.14 supports: `cloud {}` block, `moved` blocks, `import` blocks, `check` blocks, provider-defined functions, ephemeral values, write-only attributes
- The HCP Terraform workspace should also be pinned to `>= 1.14` in its settings to ensure consistency between local and remote execution
- The `>=` operator (not `~>`) is used for `required_version` per constitution guidance -- consumers want broad forward compatibility

### Modules Identified

No infrastructure modules are needed for workspace configuration itself -- this is a configuration pattern, not a module deployment. The workspace configuration provides the foundation for the infrastructure modules researched separately.

- **Private Module (reference only)**: `app.terraform.io/hashi-demos-apj/workspace/tfe` v-latest
  - **Purpose**: Could be used in a bootstrap workspace to create the `sandbox_consumer_web_stack` workspace programmatically
  - **Key Inputs**: `name`, `organization`, `project_id`, `terraform_version`, `execution_mode`
  - **Key Outputs**: `id`, `html_url`
  - **Note**: This module manages TFE workspaces -- it is NOT used inside the consumer code itself. The consumer code uses the `cloud {}` block to connect to an already-existing workspace.

- **Glue Resources Needed**: None for workspace configuration
- **Wiring Considerations**: The `cloud {}` block is the entry point -- all other configuration (provider, modules, variables) depends on a successful `terraform init` against the workspace

### Rationale

The `cloud {}` block with dynamic provider credentials is the canonical HCP Terraform pattern. It eliminates static credentials, provides automatic state management, and integrates with HCP Terraform's run pipeline (speculative plans on PRs, cost estimation, policy checks). The consumer constitution explicitly mandates this approach (Section 1.3, 3.1). The `hashi-demos-apj` organization has an existing `workspace/tfe` private module that could bootstrap workspaces, but for consumer code the workspace is assumed to pre-exist.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| `backend "remote" {}` | Legacy syntax; lacks project support; `cloud {}` is the modern replacement |
| `backend "s3" {}` with DynamoDB lock | Requires managing state infrastructure; loses HCP Terraform features (run pipeline, cost estimation, policy enforcement) |
| Static AWS credentials in workspace variables | Violates consumer constitution Section 3.1; long-lived credentials are a security risk; dynamic credentials via OIDC are mandated |
| `backend "local" {}` | No state sharing, locking, or remote execution; unsuitable for team workflows |
| Provider version `~> 6.0` | Only needed if private registry modules require it; start with `~> 5.0` and bump if module dependencies require 6.x |

### Sources

- HCP Terraform documentation: [Cloud Block Configuration](https://developer.hashicorp.com/terraform/language/settings/terraform-cloud)
- HCP Terraform documentation: [Dynamic Provider Credentials for AWS](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/aws-configuration)
- TFE provider v0.74.1: `tfe_workspace` resource and data source documentation
- TFE provider v0.74.1: `tfe_variable_set` resource and data source documentation
- TFE provider v0.74.1: `tfe_variable` resource documentation
- AWS provider v6.x: `default_tags` configuration block documentation
- Consumer constitution: `.foundations/memory/consumer-constitution.md` Sections 1.3, 2.1, 3.1, 3.3, 4.1, 4.2
- Project MEMORY.md: Provider version notes (SNS module may require `>= 6.9`)
