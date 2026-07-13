variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "devops-mcp"
}

variable "alert_email" {
  description = "Where AWS Budget alerts (and later, incident notifications) are sent."
  type        = string
}

variable "monthly_budget_usd" {
  type    = string
  default = "5"
}

variable "github_repo" {
  description = "GitHub repo in \"owner/name\" form, used to scope the GitHub Actions OIDC trust policy."
  type        = string
}

variable "pagerduty_user_email" {
  description = "Email of the PagerDuty user (from signup) to put on the escalation policy."
  type        = string
}
