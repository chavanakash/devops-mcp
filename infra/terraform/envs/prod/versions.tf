terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.0"
    }
    pagerduty = {
      source  = "PagerDuty/pagerduty"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    # Filled in via `terraform init -backend-config=backend.hcl`
    # (see backend.hcl.example). Values depend on the AWS account ID, so they
    # aren't hardcoded here.
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Env       = "prod"
    }
  }
}

# Credentials read from env: DD_API_KEY / DD_APP_KEY — never set here.
provider "datadog" {}

# Credentials read from env: PAGERDUTY_TOKEN — never set here.
provider "pagerduty" {}
