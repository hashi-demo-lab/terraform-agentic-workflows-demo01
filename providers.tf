provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Application = var.application_name
      Owner       = var.owner
    }
  }

  # Dynamic credentials via HCP Terraform
  # agent_AWS_Dynamic_Creds variable set injects:
  #   TFC_AWS_PROVIDER_AUTH = true
  #   TFC_AWS_RUN_ROLE_ARN = arn:aws:iam::855831148133:role/tfstacks-role
  #   TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE = aws.workload.identity
}
