resource "google_monitoring_dashboard" "main" {
  project = var.config.gcp.project_id

  dashboard_json = jsonencode({
    displayName = "${local.resource_prefix} overview"
    gridLayout = {
      columns = 2
      widgets = concat(
        [
          for chart in [
            { title = "VM CPU", filter = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\"" },
            { title = "VM memory", filter = "resource.type=\"gce_instance\" AND metric.type=\"agent.googleapis.com/memory/percent_used\" AND metric.label.state=\"used\"" },
            { title = "VM disk", filter = "resource.type=\"gce_instance\" AND metric.type=\"agent.googleapis.com/disk/percent_used\" AND metric.label.state=\"used\"" },
            { title = "RabbitMQ connections", filter = "resource.type=\"prometheus_target\" AND metric.type=\"prometheus.googleapis.com/rabbitmq_connections/gauge\"" },
            { title = "RabbitMQ queued messages", filter = "resource.type=\"prometheus_target\" AND metric.type=\"prometheus.googleapis.com/rabbitmq_queue_messages_ready/gauge\"" },
            { title = "Redis memory", filter = "resource.type=\"prometheus_target\" AND metric.type=\"prometheus.googleapis.com/redis_memory_used_bytes/gauge\"" },
            { title = "Cloud SQL CPU", filter = "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" AND resource.label.database_id=\"${var.config.gcp.project_id}:${local.resource_prefix}-postgresql\"" },
            { title = "Cloud SQL disk", filter = "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/disk/utilization\" AND resource.label.database_id=\"${var.config.gcp.project_id}:${local.resource_prefix}-postgresql\"" },
            ] : {
            title = chart.title
            xyChart = {
              dataSets = [{
                plotType = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = chart.filter
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
              yAxis = { scale = "LINEAR" }
            }
          }
        ],
        [
          for name, check in google_monitoring_uptime_check_config.ui : {
            title = "UI availability"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.check_id=\"${check.uptime_check_id}\""
                  aggregation = {
                    alignmentPeriod    = "300s"
                    perSeriesAligner   = "ALIGN_NEXT_OLDER"
                    crossSeriesReducer = "REDUCE_FRACTION_TRUE"
                  }
                }
              }
            }
          }
        ],
      )
    }
  })
}
