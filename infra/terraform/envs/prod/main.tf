data "aws_caller_identity" "current" {}

locals {
  account_id           = data.aws_caller_identity.current.account_id
  state_bucket_arn     = "arn:aws:s3:::${var.project}-tfstate-${local.account_id}"
  state_lock_table_arn = "arn:aws:dynamodb:${var.aws_region}:${local.account_id}:table/${var.project}-tfstate-lock"
}

module "budget_alarm" {
  source = "../../modules/budget-alarm"

  project           = var.project
  alert_email       = var.alert_email
  monthly_limit_usd = var.monthly_budget_usd
}

module "static_site" {
  source = "../../modules/static-site"

  project     = var.project
  bucket_name = "${var.project}-site-${local.account_id}"
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  project              = var.project
  github_repo          = var.github_repo
  state_bucket_arn     = local.state_bucket_arn
  state_lock_table_arn = local.state_lock_table_arn
}

module "k3s_node" {
  source = "../../modules/k3s-node"

  project              = var.project
  github_repo          = var.github_repo
  deploy_datadog_agent = var.enable_datadog
}

module "ecr" {
  source = "../../modules/ecr"

  project = var.project
}

# Datadog/PagerDuty are opt-in (default off) so the first apply doesn't need
# those accounts/credentials at all. Flip enable_pagerduty / enable_datadog to
# true in terraform.tfvars once you've set them up — see SETUP.md.
module "pagerduty" {
  source = "../../modules/pagerduty"
  count  = var.enable_pagerduty ? 1 : 0

  project    = var.project
  user_email = var.pagerduty_user_email
}

module "datadog" {
  source = "../../modules/datadog"
  count  = var.enable_datadog ? 1 : 0

  project       = var.project
  notify_handle = "@pagerduty-${var.project}-status-api"
}
