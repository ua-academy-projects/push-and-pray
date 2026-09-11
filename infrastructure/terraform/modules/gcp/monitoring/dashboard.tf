locals {
  gauge = { aligner = "ALIGN_MEAN", reducer = "REDUCE_MAX", group_by = ["resource.label.instance_id"] }

  charts = [
    merge(local.gauge, { title = "CPU utilisation", metric = "compute.googleapis.com/instance/cpu/utilization", extra = "" }),
    merge(local.gauge, { title = "Memory used, %", metric = "agent.googleapis.com/memory/percent_used", extra = " AND metric.labels.state=\"used\"" }),
    merge(local.gauge, { title = "Disk used, %", metric = "agent.googleapis.com/disk/percent_used", extra = local.used_disk }),
  ]

  tiles = [
    for index, chart in local.charts : {
      width  = 4
      height = 4
      xPos   = index % 3 * 4
      yPos   = floor(index / 3) * 4

      widget = {
        title = chart.title

        xyChart = {
          dataSets = [{
            plotType = "LINE"

            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "metric.type=\"${chart.metric}\" AND resource.type=\"gce_instance\"${chart.extra}"

                aggregation = {
                  alignmentPeriod    = "300s"
                  perSeriesAligner   = chart.aligner
                  crossSeriesReducer = chart.reducer
                  groupByFields      = chart.group_by
                }
              }
            }
          }]
        }
      }
    }
  ]
}

resource "google_monitoring_dashboard" "overview" {
  count = local.enabled

  dashboard_json = jsonencode({
    displayName  = "${local.prefix} overview"
    mosaicLayout = { columns = 12, tiles = local.tiles }
  })
}
