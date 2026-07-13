variable "project" {
  type = string
}

variable "monthly_limit_usd" {
  description = "Monthly spend limit in USD. Kept low since this project is designed to stay in the AWS free tier."
  type        = string
  default     = "5"
}

variable "alert_email" {
  description = "Email address to notify at 50/80/100% of budget and on forecasted overspend."
  type        = string
}
