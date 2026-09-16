locals {
  instance_filter = join(" OR ", [
    for instance in values(var.instances) :
    "resource.label.instance_id=\"${instance.instance_id}\""
  ])

  charts = [
    { title = "CPU utilization", metric = "compute.googleapis.com/instance/cpu/utilization", aligner = "ALIGN_MEAN" },
    { title = "Memory used", metric = "agent.googleapis.com/memory/percent_used", aligner = "ALIGN_MEAN" },
    { title = "Disk used", metric = "agent.googleapis.com/disk/percent_used", aligner = "ALIGN_MEAN" },
    { title = "Network received bytes", metric = "compute.googleapis.com/instance/network/received_bytes_count", aligner = "ALIGN_RATE" },
    { title = "Network sent bytes", metric = "compute.googleapis.com/instance/network/sent_bytes_count", aligner = "ALIGN_RATE" },
    { title = "Disk read bytes", metric = "compute.googleapis.com/instance/disk/read_bytes_count", aligner = "ALIGN_RATE" },
    { title = "Disk write bytes", metric = "compute.googleapis.com/instance/disk/write_bytes_count", aligner = "ALIGN_RATE" },
  ]

  database_charts = var.database_instance_id == null ? [] : [
    { title = "Cloud SQL CPU utilization", metric = "cloudsql.googleapis.com/database/cpu/utilization" },
    { title = "Cloud SQL memory utilization", metric = "cloudsql.googleapis.com/database/memory/utilization" },
    { title = "Cloud SQL disk utilization", metric = "cloudsql.googleapis.com/database/disk/utilization" },
  ]
}

resource "google_monitoring_dashboard" "main" {
  dashboard_json = jsonencode({
    displayName = "${var.resource_prefix}-gcp"
    mosaicLayout = {
      columns = 48
      tiles = concat(
        [{
          xPos   = 0, yPos = 0, width = 48, height = 4
          widget = { text = { content = "# OilScope GCP monitoring\nEmail notifications are sent when incidents open and close.", format = "MARKDOWN" } }
        }],
        [for index, chart in local.charts : {
          xPos   = index % 2 == 0 ? 0 : 24
          yPos   = 4 + floor(index / 2) * 16
          width  = 24
          height = 16
          widget = {
            title = chart.title
            xyChart = {
              dataSets = [{
                plotType = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"${chart.metric}\" AND resource.type=\"gce_instance\" AND (${local.instance_filter})"
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = chart.aligner
                    }
                  }
                }
              }]
              yAxis = { scale = "LINEAR" }
            }
          }
        }],
        [for index, chart in local.database_charts : {
          xPos   = index % 2 == 0 ? 0 : 24
          yPos   = 84 + floor(index / 2) * 16
          width  = 24
          height = 16
          widget = {
            title = chart.title
            xyChart = {
              dataSets = [{
                plotType = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"${chart.metric}\" AND resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${var.project_id}:${var.database_instance_id}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
              yAxis = { scale = "LINEAR" }
            }
          }
        }],
        [{
          xPos = 24, yPos = 52, width = 24, height = 16
          widget = {
            title = "HTTPS uptime"
            xyChart = {
              dataSets = [{
                plotType = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter      = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\""
                    aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_FRACTION_TRUE" }
                  }
                }
              }]
              yAxis = { scale = "LINEAR" }
            }
          }
          }, {
          xPos = 0, yPos = 68, width = 48, height = 16
          widget = {
            title = "Recent application errors"
            logsPanel = {
              filter = "resource.type=\"gce_instance\" AND log_id(\"oilscope_application\") AND (severity>=ERROR OR jsonPayload.MESSAGE =~ \"ERROR|HTTP/[0-9.]+.* 5[0-9][0-9]\" OR textPayload =~ \"ERROR|HTTP/[0-9.]+.* 5[0-9][0-9]\")"
            }
          }
        }]
      )
    }
  })
}
