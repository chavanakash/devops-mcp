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
