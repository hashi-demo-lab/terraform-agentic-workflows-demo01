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
      version = "~> 6.19"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
