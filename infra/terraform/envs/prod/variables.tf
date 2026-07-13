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
  description = "Email of the PagerDuty user (from signup) to put on the escalation policy. Only required if enable_pagerduty = true."
  type        = string
  default     = ""
}

variable "enable_pagerduty" {
  description = "Provision the PagerDuty escalation policy/service. Requires PAGERDUTY_TOKEN in the environment when true."
  type        = bool
  default     = false
}

variable "enable_datadog" {
  description = "Provision Datadog monitors/dashboard, and deploy the Datadog Agent DaemonSet to the cluster. Requires DD_API_KEY/DD_APP_KEY in the environment when true."
  type        = bool
  default     = false
}
