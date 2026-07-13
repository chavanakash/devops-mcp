output "site_url" {
  value = module.static_site.url
}

output "site_bucket" {
  value = module.static_site.bucket_name
}

output "cloudfront_distribution_id" {
  value = module.static_site.distribution_id
}

output "github_oidc_plan_role_arn" {
  value = module.github_oidc.plan_role_arn
}

output "github_oidc_deploy_role_arn" {
  value = module.github_oidc.deploy_role_arn
}

output "k3s_node_instance_id" {
  value = module.k3s_node.instance_id
}

output "k3s_node_public_ip" {
  value = module.k3s_node.public_ip
}

output "status_api_url" {
  value = module.k3s_node.status_api_url
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "datadog_dashboard_url" {
  value = module.datadog.dashboard_url
}

output "pagerduty_service_id" {
  value = module.pagerduty.service_id
}
