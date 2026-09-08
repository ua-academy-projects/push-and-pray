resource "google_monitoring_alert_policy" "high_cpu" {
  project      = var.project_id
  display_name = "${var.resource_prefix} high CPU"
  combiner     = "OR"
  severity     = "WARNING"
  enabled      = true

  conditions {
    display_name = "CPU utilization above ${var.settings.cpu.threshold_percent}%"

    condition_threshold {
      filter          = local.cpu_filter
      comparison      = "COMPARISON_GT"
      threshold_value = var.settings.cpu.threshold_percent / 100
      duration        = "${var.settings.cpu.duration_seconds}s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = local.notification_channels
  user_labels           = var.labels
}

resource "google_monitoring_alert_policy" "high_disk" {
  project      = var.project_id
  display_name = "${var.resource_prefix} high disk usage"
  combiner     = "OR"
  severity     = "WARNING"
  enabled      = true

  conditions {
    display_name = "Disk usage above ${var.settings.disk.threshold_percent}%"

    condition_threshold {
      filter          = local.disk_filter
      comparison      = "COMPARISON_GT"
      threshold_value = var.settings.disk.threshold_percent
      duration        = "${var.settings.disk.duration_seconds}s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = local.notification_channels
  user_labels           = var.labels
}

resource "google_monitoring_alert_policy" "container_errors" {
  count = var.settings.logs.enabled ? 1 : 0

  project      = var.project_id
  display_name = "${var.resource_prefix} container errors"
  combiner     = "OR"
  severity     = "ERROR"
  enabled      = true

  conditions {
    display_name = "Docker log contains an error marker"

    condition_matched_log {
      filter = local.log_filter
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }

    auto_close = "1800s"
  }

  notification_channels = local.notification_channels
  user_labels           = var.labels
}
