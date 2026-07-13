variable "aws_region" {
  description = "AWS region for the state bucket / lock table."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Short project name used to prefix resource names."
  type        = string
  default     = "devops-mcp"
}

variable "aws_profile" {
  description = "Named AWS CLI profile to use. Empty string falls back to the default credential chain."
  type        = string
  default     = ""
}
