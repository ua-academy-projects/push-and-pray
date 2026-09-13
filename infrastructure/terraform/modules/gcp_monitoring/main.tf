locals {
  cpu_enabled       = var.monitoring.enabled && var.monitoring.cpu.enabled && length(var.vms) > 0
  lifecycle_enabled = var.monitoring.enabled && var.monitoring.lifecycle.enabled && length(var.monitoring.lifecycle.notify_states) > 0 && length(var.vms) > 0
  enabled           = local.cpu_enabled || local.lifecycle_enabled
  cpu_vms           = local.cpu_enabled ? var.vms : {}
  lifecycle_vms     = local.lifecycle_enabled ? var.vms : {}

  cpu_filter = join(" OR ", [
    for vm in values(var.vms) : "resource.labels.instance_id=\"${vm.instance_id}\""
  ])

  lifecycle_event_filters = compact([
    contains(var.monitoring.lifecycle.notify_states, "stopped") ? "(log_id(\"cloudaudit.googleapis.com/activity\") AND protoPayload.methodName=(\"beta.compute.instances.stop\" OR \"v1.compute.instances.stop\") AND operation.first=true)" : "",
    contains(var.monitoring.lifecycle.notify_states, "terminated") ? "(log_id(\"cloudaudit.googleapis.com/system_event\") AND protoPayload.methodName=(\"compute.instances.hostError\" OR \"compute.instances.guestTerminate\" OR \"compute.instances.terminateOnHostMaintenance\"))" : "",
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
  count = local.cpu_enabled ? 1 : 0

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
  for_each = local.cpu_vms

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

resource "google_monitoring_alert_policy" "lifecycle" {
  for_each = local.lifecycle_vms

  display_name = "${each.value.name} lifecycle event"
  combiner     = "OR"

  conditions {
    display_name = "VM entered a configured lifecycle state"

    condition_matched_log {
      filter = "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${each.value.instance_id}\" AND (${join(" OR ", local.lifecycle_event_filters)})"
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
  }

  notification_channels = [google_monitoring_notification_channel.email[0].name]
}
