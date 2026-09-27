resource "google_monitoring_alert_policy" "high_cpu" {
  for_each = var.instance_keys

  display_name = "${var.instances[each.key].name} high CPU Utilization"
  combiner     = "OR"
  enabled      = true
  conditions {
    display_name = "${var.instances[each.key].name} CPU usage above 80%"
    condition_threshold {
      filter = join(" AND ", [
        "resource.type=\"gce_instance\"",
        "metric.type=\"compute.googleapis.com/instance/cpu/utilization\"",
        "resource.labels.instance_id=\"${var.instances[each.key].instance_id}\""
      ])

      comparison      = "COMPARISON_GT"
      duration        = "300s"
      threshold_value = 0.8 # 0.8 in GCP means 80% CPU utilization.
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }

      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email[0].name
  ]

  documentation {
    content = <<-EOT
      CPU utilization for ${var.instances[each.key].name} has been above 80%
      for at least five minutes.
    EOT

    mime_type = "text/markdown"
  }
}

resource "google_monitoring_notification_channel" "email" {
  count = length(var.instance_keys) > 0 ? 1 : 0

  display_name = "${var.name_prefix} infrastructure alerts"
  type         = "email"

  labels = {
    email_address = var.notification_email
  }
}

resource "google_monitoring_dashboard" "infrastructure" {
  count = length(var.instance_keys) > 0 ? 1 : 0

  dashboard_json = jsonencode({
    displayName = "${var.name_prefix} Infrastructure Dashboard"

    mosaicLayout = {
      columns = 24
      tiles = [
        for index, instance in values(var.instances) : {
          xPos   = 0
          yPos   = index * 6
          width  = 24
          height = 6

          widget = {
            title = "${instance.name} CPU Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = join(" AND ", [
                        "resource.type=\"gce_instance\"",
                        "metric.type=\"compute.googleapis.com/instance/cpu/utilization\"",
                        "resource.labels.instance_id=\"${instance.instance_id}\""
                      ])

                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }

                  plotType   = "LINE"
                  targetAxis = "Y1"
                }
              ]

              timeshiftDuration = "0s"

              yAxis = {
                label = "CPU utilization"
                scale = "LINEAR"
              }

              chartOptions = {
                mode = "COLOR"
              }
            }
          }
        }
      ]
    }
  })
}
