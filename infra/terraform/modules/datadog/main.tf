# Dashboards and monitors as code. Requires DD_API_KEY / DD_APP_KEY in the
# environment (the datadog provider reads them automatically — never passed as
# Terraform variables). The Datadog Agent itself runs as a DaemonSet in the k3s
# cluster (see k8s/datadog-agent/) and is what actually ships host/container
# metrics; this module only configures what Datadog does with them.

resource "datadog_synthetics_test" "status_api_uptime" {
  name      = "${var.project} status-api uptime"
  type      = "api"
  subtype   = "http"
  status    = "live"
  message   = "status-api is unreachable. ${var.notify_handle}"
  locations = ["aws:ap-south-1"]

  request_definition {
    method = "GET"
    url    = "${var.status_api_url}/health"
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "200"
  }

  options_list {
    tick_every = 300 # every 5 minutes — plenty for a portfolio demo, minimal API usage
    retry {
      count    = 2
      interval = 300
    }
    monitor_options {
      renotify_interval = 60
    }
  }

  tags = [var.project]
}

resource "datadog_monitor" "host_cpu_high" {
  name    = "${var.project} k3s node CPU high"
  type    = "metric alert"
  message = <<-EOT
    k3s node CPU has been above 85% for 10 minutes.
    See runbooks/high-error-rate.md for triage steps. ${var.notify_handle}
  EOT

  query = "avg(last_10m):avg:system.cpu.user{project:${var.project}} > 85"

  monitor_thresholds {
    critical = 85
    warning  = 70
  }

  notify_no_data    = false
  renotify_interval = 60
  tags              = [var.project]
}

resource "datadog_dashboard" "overview" {
  title       = "${var.project} — infra overview"
  description = "Single-node k3s cluster + status-api, deployed via GitOps."
  layout_type = "ordered"

  widget {
    group_definition {
      title       = "status-api"
      layout_type = "ordered"

      widget {
        check_status_definition {
          title    = "Uptime check"
          check    = "status-api.uptime"
          group    = "*"
          grouping = "cluster"
        }
      }

      widget {
        timeseries_definition {
          title = "Requests"
          request {
            q            = "sum:trace.express.request.hits{service:status-api}.as_count()"
            display_type = "bars"
          }
        }
      }
    }
  }

  widget {
    group_definition {
      title       = "k3s node"
      layout_type = "ordered"

      widget {
        timeseries_definition {
          title = "CPU"
          request {
            q            = "avg:system.cpu.user{project:${var.project}}"
            display_type = "line"
          }
        }
      }

      widget {
        timeseries_definition {
          title = "Memory used"
          request {
            q            = "avg:system.mem.used{project:${var.project}}"
            display_type = "line"
          }
        }
      }
    }
  }
}
