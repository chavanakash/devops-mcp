# Requires PAGERDUTY_TOKEN in the environment. Targets the PagerDuty user created
# at account signup (var.user_email) rather than provisioning new users — this is a
# solo portfolio project, not a team.

data "pagerduty_user" "on_call" {
  email = var.user_email
}

resource "pagerduty_escalation_policy" "primary" {
  name      = "${var.project}-primary"
  num_loops = 2

  rule {
    escalation_delay_in_minutes = var.escalation_delay_minutes
    target {
      type = "user_reference"
      id   = data.pagerduty_user.on_call.id
    }
  }
}

resource "pagerduty_service" "status_api" {
  name              = "${var.project}-status-api"
  description       = "status-api and the k3s node it runs on."
  escalation_policy = pagerduty_escalation_policy.primary.id
  alert_creation    = "create_alerts_and_incidents"

  incident_urgency_rule {
    type    = "constant"
    urgency = "high"
  }
}

# Events API v2 key — Datadog monitors send alerts here via Datadog's PagerDuty
# integration (installed once in the Datadog UI: Integrations -> PagerDuty,
# using this key). Not something Terraform can wire on the Datadog side.
resource "pagerduty_service_integration" "datadog" {
  name    = "Datadog"
  service = pagerduty_service.status_api.id
  vendor  = data.pagerduty_vendor.datadog.id
}

data "pagerduty_vendor" "datadog" {
  name = "Datadog"
}
