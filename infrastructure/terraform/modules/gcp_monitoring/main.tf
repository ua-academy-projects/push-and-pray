locals {
  cpu_enabled       = var.monitoring.enabled && var.monitoring.cpu.enabled && length(var.vms) > 0
  lifecycle_enabled = var.monitoring.enabled && var.monitoring.lifecycle.enabled && length(var.monitoring.lifecycle.notify_states) > 0 && length(var.vms) > 0
  http_5xx_ui_vms = var.monitoring.enabled && var.monitoring.http_5xx.enabled ? {
    for name, vm in var.vms : name => vm if vm.role == "ui"
  } : {}
  http_5xx_enabled  = length(local.http_5xx_ui_vms) > 0
  dashboard_enabled = local.cpu_enabled || local.http_5xx_enabled
  enabled           = local.dashboard_enabled || local.lifecycle_enabled
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
  count = local.dashboard_enabled ? 1 : 0

  dashboard_json = jsonencode({
    displayName = "${var.resource_prefix} monitoring"
    mosaicLayout = {
      columns = 12
      tiles = concat(local.cpu_enabled ? [{
        width  = 12
        height = 8
        xPos   = 0
        yPos   = 0
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
        }] : [], local.http_5xx_enabled ? [{
        width  = 12
        height = 8
        xPos   = 0
        yPos   = local.cpu_enabled ? 8 : 0
        widget = {
          title = "Traefik HTTP 5xx responses"
          xyChart = {
            dataSets = [
              for name, vm in local.http_5xx_ui_vms : {
                plotType = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.http_5xx[name].name}\" AND resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${vm.instance_id}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_SUM"
                    }
                  }
                }
              }
            ]
            yAxis = {
              label = "5xx responses"
              scale = "LINEAR"
            }
          }
        }
      }] : [])
    }
  })
}

resource "google_project_iam_member" "http_log_writer" {
  for_each = local.http_5xx_ui_vms

  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${each.value.service_account_email}"
}

resource "google_logging_metric" "http_5xx" {
  for_each = local.http_5xx_ui_vms

  name        = "${replace(var.resource_prefix, "-", "_")}_traefik_http_5xx"
  description = "Count of downstream HTTP 500-599 responses returned by Traefik"
  filter      = "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${each.value.instance_id}\" AND log_id(\"traefik_access\") AND jsonPayload.DownstreamStatus >= 500 AND jsonPayload.DownstreamStatus < 600"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_alert_policy" "http_5xx" {
  for_each = local.http_5xx_ui_vms

  display_name = "${each.value.name} HTTP 5xx responses"
  combiner     = "OR"

  conditions {
    display_name = "At least ${var.monitoring.http_5xx.threshold_count} HTTP 5xx responses in ${var.monitoring.http_5xx.duration_minutes} minutes"

    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.http_5xx[each.key].name}\" AND resource.labels.instance_id=\"${each.value.instance_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.monitoring.http_5xx.threshold_count - 1
      duration        = "0s"

      aggregations {
        alignment_period   = "${var.monitoring.http_5xx.duration_minutes * 60}s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email[0].name]
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
