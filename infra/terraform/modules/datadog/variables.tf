variable "project" {
  type = string
}

variable "status_api_url" {
  description = "Public URL of status-api, monitored via a Datadog synthetic/HTTP check."
  type        = string
}

variable "notify_handle" {
  description = "Datadog notification target for monitor alerts, e.g. \"@slack-incidents\" or \"@pagerduty-devops-mcp\"."
  type        = string
  default     = ""
}
