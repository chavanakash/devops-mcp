# Dashboards and monitors as code. Requires DD_API_KEY / DD_APP_KEY in the
# environment (the datadog provider reads them automatically — never passed as
# Terraform variables). The Datadog Agent itself runs as a DaemonSet in the k3s
# cluster (see k8s/datadog-agent/) and is what actually ships host/container
# metrics; this module only configures what Datadog does with them.
#
# Deliberately free-tier only: Datadog's free plan is Infrastructure Monitoring
# only (5 hosts, 1-day retention) — no Synthetics, APM, or Logs. The status-api
# uptime check below is therefore an Agent-side HTTP check (reports the
# `network.http.can_connect` service check, configured via
# k8s/datadog-agent/http-check-configmap.yaml), not `datadog_synthetics_test`,
# which is a paid-only product.

resource "datadog_monitor" "status_api_uptime" {
  name    = "${var.project} status-api unreachable"
  type    = "service check"
  message = "status-api's Agent-side HTTP check is failing. ${var.notify_handle}"

  query = "\"network.http.can_connect\".over(\"instance:status-api\").by(\"*\").last(3).count_by_status()"

  monitor_thresholds {
    critical = 3
    warning  = 1
    ok       = 1
  }

  notify_no_data    = false
  renotify_interval = 60
  tags              = [var.project]
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
          title    = "Uptime check (Agent HTTP check)"
          check    = "network.http.can_connect"
          group    = "*"
          grouping = "cluster"
          tags     = ["instance:status-api"]
        }
      }

      widget {
        note_definition {
          content          = "Request-level tracing (APM) isn't in Datadog's free tier. For live request counts, see the portfolio site's \"Live infra\" widget, which reads status-api's own /stats endpoint directly."
          background_color = "gray"
          font_size        = "14"
          text_align       = "left"
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
