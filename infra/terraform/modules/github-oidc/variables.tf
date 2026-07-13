variable "project" {
  type = string
}

variable "github_repo" {
  description = "GitHub repo in \"owner/name\" form allowed to assume these roles."
  type        = string
}

variable "state_bucket_arn" {
  description = "ARN of the Terraform remote-state S3 bucket, so CI can read/write state."
  type        = string
}

variable "state_lock_table_arn" {
  description = "ARN of the Terraform state-lock DynamoDB table."
  type        = string
}
