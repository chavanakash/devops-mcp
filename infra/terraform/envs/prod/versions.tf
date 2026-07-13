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
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Env       = "prod"
    }
  }
}

# Credentials read from env: DD_API_KEY / DD_APP_KEY — never set here. Terraform
# configures every declared provider block eagerly, even with zero resources
# referencing it (enable_datadog = false), so `validate` is what lets `plan`/
# `apply` succeed without those env vars set at all until they're needed.
provider "datadog" {
  validate = var.enable_datadog
}

# Credentials read from env: PAGERDUTY_TOKEN — never set here. Same eager-config
# issue: an explicit non-empty placeholder is required when disabled, since the
# provider errors on a completely absent token regardless of resource count.
provider "pagerduty" {
  token                       = var.enable_pagerduty ? null : "unset"
  skip_credentials_validation = !var.enable_pagerduty
}
