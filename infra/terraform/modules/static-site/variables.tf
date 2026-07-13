variable "project" {
  type = string
}

variable "bucket_name" {
  description = "Globally-unique S3 bucket name for the site origin."
  type        = string
}

variable "api_origin_ip" {
  description = "Public IP of the k3s node running status-api. Proxied on /api/* so the browser only ever talks to CloudFront's HTTPS origin — status-api itself has no TLS."
  type        = string
}

variable "api_origin_port" {
  type    = number
  default = 30080
}
