resource "google_monitoring_dashboard" "overview" {
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = "${var.resource_prefix} overview"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          xPos   = 0
          yPos   = 0
          width  = 6
          height = 4
          widget = {
            title = "VM CPU utilization"
            xyChart = {
              dataSets = [{
                plotType = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = local.cpu_filter
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
        },
        {
          xPos   = 6
          yPos   = 0
          width  = 6
          height = 4
          widget = {
            title = "VM disk usage"
            xyChart = {
              dataSets = [{
                plotType = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = local.disk_filter
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
              yAxis = {
                label = "Percent used"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          xPos   = 0
          yPos   = 4
          width  = 12
          height = 4
          widget = {
            title = "Docker container logs"
            logsPanel = {
              filter        = "resource.type=\"gce_instance\""
              resourceNames = ["projects/${var.project_id}"]
            }
          }
        }
      ]
    }
  })
}
