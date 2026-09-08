resource "google_monitoring_uptime_check_config" "ui" {
  count = var.settings.uptime.enabled ? 1 : 0

  project            = var.project_id
  display_name       = "${var.resource_prefix} UI HTTPS"
  timeout            = "${var.settings.uptime.timeout_seconds}s"
  period             = "${var.settings.uptime.period_seconds}s"
  checker_type       = "STATIC_IP_CHECKERS"
  log_check_failures = true
  user_labels        = var.labels

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.uptime_hostname
    }
  }

  http_check {
    path           = var.settings.uptime.path
    port           = 443
    request_method = "GET"
    use_ssl        = true
    validate_ssl   = true
  }

  lifecycle {
    precondition {
      condition     = var.uptime_hostname != null && var.uptime_hostname != ""
      error_message = "Uptime monitoring is enabled, but no GCP VM with role ui and public_endpoint.hostname was found."
    }
  }
}

resource "google_monitoring_alert_policy" "ui_unavailable" {
  count = var.settings.uptime.enabled ? 1 : 0

  project      = var.project_id
  display_name = "${var.resource_prefix} UI unavailable"
  combiner     = "OR"
  severity     = "CRITICAL"
  enabled      = true

  conditions {
    display_name = "HTTPS uptime check failed"

    condition_threshold {
      filter = "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.check_id=\"${google_monitoring_uptime_check_config.ui[0].uptime_check_id}\""

      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = "120s"

      aggregations {
        alignment_period   = "120s"
        per_series_aligner = "ALIGN_FRACTION_TRUE"
      }

      trigger {
        percent = 0.5
      }
    }
  }

  notification_channels = local.notification_channels
  user_labels           = var.labels
}
