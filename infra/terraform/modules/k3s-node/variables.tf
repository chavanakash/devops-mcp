variable "project" {
  type = string
}

variable "instance_type" {
  description = "Free-tier eligible: t3.micro (or t2.micro depending on account/region)."
  type        = string
  default     = "t3.micro"
}

variable "status_api_nodeport" {
  description = "The only inbound port open to the internet — the status-api demo service."
  type        = number
  default     = 30080
}

variable "github_repo" {
  description = "owner/name — Argo CD is bootstrapped to track k8s/status-api on this repo's main branch."
  type        = string
}
