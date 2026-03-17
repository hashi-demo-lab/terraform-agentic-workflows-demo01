terraform {
  required_version = ">= 1.5.7"

  cloud {
    organization = "hashi-demos-apj"
    hostname     = "app.terraform.io"

    workspaces {
      name    = "terraform-agentic-workflows-demo01"
      project = "sandbox"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.5"
    }
  }
}
