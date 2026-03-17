provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Owner       = var.owner
      Application = var.application_name
    }
  }

  # Dynamic credentials injected by HCP Terraform -- no static keys
}
