resource "google_monitoring_alert_policy" "vm" {
  for_each              = local.alarms_enabled ? local.vm_signals : {}
  project               = local.project_id
  display_name          = "${local.resource_prefix}-${each.key}"
  combiner              = "OR"
  notification_channels = local.notification_channels
  user_labels           = local.common_labels
  conditions {
    display_name = "${each.value.name} ${each.value.signal} sustained high"
    condition_threshold {
      filter                  = each.value.filter
      comparison              = "COMPARISON_GT"
      threshold_value         = each.value.threshold
      duration                = "600s"
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = each.value.aligner
      }
      trigger { count = 1 }
    }
  }
  depends_on = [google_project_service.monitoring]
}
resource "google_monitoring_alert_policy" "missing" {
  for_each              = local.alarms_enabled ? local.absence_signals : {}
  project               = local.project_id
  display_name          = "${local.resource_prefix}-${each.key}"
  combiner              = "OR"
  notification_channels = local.notification_channels
  user_labels           = local.common_labels
  conditions {
    display_name = "${each.value.name} telemetry absent"
    condition_absent {
      filter   = each.value.filter
      duration = "600s"
      trigger { count = 1 }
    }
  }
  documentation {
    content   = "Assumes an always-on VM with previously observed telemetry. Check VM state, Ops Agent, IAM and network access; a never-seen metric is not a proven healthy host."
    mime_type = "text/markdown"
  }
  depends_on = [google_project_service.monitoring]
}
resource "google_monitoring_alert_policy" "http" {
  for_each              = local.alarms_enabled && local.logs_enabled ? local.http_filters : {}
  project               = local.project_id
  display_name          = "${local.resource_prefix}-${each.key}"
  combiner              = "OR"
  notification_channels = local.notification_channels
  user_labels           = local.common_labels
  conditions {
    display_name = "Traefik ${each.key}"
    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.http[each.key].name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = local.settings.http_error_threshold - 1
      duration        = "0s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
      trigger { count = 1 }
    }
  }
}
