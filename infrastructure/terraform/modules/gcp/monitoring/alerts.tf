resource "google_monitoring_alert_policy" "cpu_high" {
    for_each = local.selected_vms

    display_name = "${local.resource_prefix}-${each.key}-cpu-high"
    combiner = "OR"

    conditions {
        display_name = "CPU utilization above threshold"

        condition_threshold {
            filter = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${var.instance_ids[each.key]}\""
            comparison = "COMPARISON_GT"
            threshold_value = local.cpu_threshold_ratio
            duration = "60s"

            aggregations {
                alignment_period = "60s"
                per_series_aligner= "ALIGN_MEAN"
            }
        }
    }
    notification_channels = [google_monitoring_notification_channel.email[0].id]
}

resource "google_monitoring_alert_policy" "instance_down" {
    for_each = local.selected_vms

    display_name = "${local.resource_prefix}-${each.key}-instance-down"
    combiner     = "OR"

    conditions {
        display_name = "CPU metric stopped reporting"

        condition_absent {
            filter   = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${var.instance_ids[each.key]}\""
            duration = "300s"

            aggregations {
                alignment_period   = "60s"
                per_series_aligner = "ALIGN_MEAN"
            }
        }
    }

  notification_channels = [google_monitoring_notification_channel.email[0].id]
}