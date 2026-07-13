variable "project" {
  type = string
}

variable "notify_handle" {
  description = "Datadog notification target for monitor alerts, e.g. \"@slack-incidents\" or \"@pagerduty-devops-mcp\"."
  type        = string
  default     = ""
}
