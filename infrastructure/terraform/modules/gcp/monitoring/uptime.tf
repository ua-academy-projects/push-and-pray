resource "google_monitoring_uptime_check_config" "health" {
  count        = local.synthetics_enabled ? 1 : 0
  project      = local.project_id
  display_name = "${local.resource_prefix}-health"
  timeout      = "30s"
  period       = "${local.settings.synthetics.period_minutes * 60}s"
  http_check {
    path         = local.settings.synthetics.path
    port         = 443
    use_ssl      = true
    validate_ssl = true
    accepted_response_status_codes { status_value = 200 }
  }
  monitored_resource {
    type   = "uptime_url"
    labels = { project_id = local.project_id, host = local.settings.synthetics.hostname }
  }
  content_matchers {
    content = "ok"
    matcher = "MATCHES_JSON_PATH"
    json_path_matcher {
      json_path    = "$.status"
      json_matcher = "EXACT_MATCH"
    }
  }
  depends_on = [google_project_service.monitoring]
}
locals {
  uptime_filter = local.synthetics_enabled ? "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.labels.check_id=\"${google_monitoring_uptime_check_config.health[0].uptime_check_id}\"" : ""
}
resource "google_monitoring_alert_policy" "uptime" {
  count                 = local.alarms_enabled && local.synthetics_enabled ? 1 : 0
  project               = local.project_id
  display_name          = "${local.resource_prefix}-health"
  combiner              = "OR"
  notification_channels = local.notification_channels
  user_labels           = local.common_labels
  conditions {
    display_name = "At least two checker locations failing"
    condition_threshold {
      filter                  = local.uptime_filter
      comparison              = "COMPARISON_GT"
      threshold_value         = 1
      duration                = "${local.settings.synthetics.period_minutes * 120}s"
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"
      aggregations {
        alignment_period     = "${local.settings.synthetics.period_minutes * 60}s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
      }
      trigger { count = 1 }
    }
  }
  conditions {
    display_name = "Uptime telemetry absent"
    condition_absent {
      filter   = local.uptime_filter
      duration = "${local.settings.synthetics.period_minutes * 180}s"
      trigger { percent = 100 }
    }
  }
}
