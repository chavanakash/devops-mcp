variable "project" {
  type = string
}

variable "user_email" {
  description = "Email of the existing PagerDuty user (created at signup) to put on-call."
  type        = string
}

variable "escalation_delay_minutes" {
  type    = number
  default = 15
}
