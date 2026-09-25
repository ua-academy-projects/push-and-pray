resource "google_monitoring_notification_channel" "email" {
  project      = var.config.gcp.project_id
  display_name = "${local.resource_prefix} alerts"
  type         = "email"
  labels = {
    email_address = var.config.monitoring.alert_email
  }
}

resource "google_monitoring_alert_policy" "system" {
  for_each = local.system_alerts

  project      = var.config.gcp.project_id
  display_name = "${local.resource_prefix} ${each.value.display_name} high"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = each.value.display_name

    condition_threshold {
      filter          = each.value.filter
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold_value
      duration        = "300s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MAX"
        group_by_fields      = each.value.group_by_fields
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  alert_strategy {
    auto_close = "1800s"
  }
}

resource "google_monitoring_alert_policy" "ui_availability" {
  for_each = google_monitoring_uptime_check_config.ui

  project      = var.config.gcp.project_id
  display_name = "${local.resource_prefix} UI unavailable"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "UI uptime check failure"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type = \"uptime_url\"",
        "metric.type = \"monitoring.googleapis.com/uptime_check/check_passed\"",
        "metric.label.check_id = \"${each.value.uptime_check_id}\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "120s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.*"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]
}
