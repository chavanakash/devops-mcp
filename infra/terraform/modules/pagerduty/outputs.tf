output "service_id" {
  value = pagerduty_service.status_api.id
}

output "datadog_integration_key" {
  value     = pagerduty_service_integration.datadog.integration_key
  sensitive = true
}
