locals {
  enabled = var.monitoring.enabled && var.monitoring.cpu.enabled && length(var.vms) > 0
  vms     = local.enabled ? var.vms : {}

  cpu_filter = join(" OR ", [
    for vm in values(var.vms) : "resource.labels.instance_id=\"${vm.instance_id}\""
  ])
}

resource "google_monitoring_notification_channel" "email" {
  count = local.enabled ? 1 : 0

  display_name = "${var.resource_prefix} monitoring email"
  type         = "email"
  labels = {
    email_address = var.monitoring.notification_email
  }
}

resource "google_monitoring_dashboard" "cpu" {
  count = local.enabled ? 1 : 0

  dashboard_json = jsonencode({
    displayName = "${var.resource_prefix} CPU"
    mosaicLayout = {
      columns = 12
      tiles = [{
        width  = 12
        height = 8
        widget = {
          title = "Compute Engine CPU utilization"
          xyChart = {
            dataSets = [{
              plotType = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\" AND (${local.cpu_filter})"
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }]
            yAxis = {
              label = "Utilization"
              scale = "LINEAR"
            }
          }
        }
      }]
    }
  })
}

resource "google_monitoring_alert_policy" "cpu" {
  for_each = local.vms

  display_name = "${each.value.name} high CPU"
  combiner     = "OR"

  conditions {
    display_name = "CPU above ${var.monitoring.cpu.threshold_percent}% for ${var.monitoring.cpu.duration_minutes} minutes"

    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.labels.instance_id=\"${each.value.instance_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.monitoring.cpu.threshold_percent / 100
      duration        = "${var.monitoring.cpu.duration_minutes * 60}s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email[0].name]
}
