locals {
  # Every metric the dashboard shows and alerting watches, in one place. The
  # filter already selects this environment's VMs by label, so neither the
  # dashboard nor an alert policy has to know a single instance. Rates are
  # per second; a null threshold means "alert when the series disappears".
  metrics = {
    for name, metric in {
      cpu = {
        title     = "CPU utilization"
        type      = "compute.googleapis.com/instance/cpu/utilization"
        aligner   = "ALIGN_MEAN"
        threshold = var.thresholds.cpu_utilization
      }
      memory = {
        title     = "Memory used"
        type      = "agent.googleapis.com/memory/bytes_used"
        extra     = "metric.label.state=\"used\""
        aligner   = "ALIGN_MEAN"
        threshold = var.thresholds.memory_used_gb * 1073741824
      }
      disk_write = {
        title     = "Disk write operations per second"
        type      = "compute.googleapis.com/instance/disk/write_ops_count"
        aligner   = "ALIGN_RATE"
        threshold = var.thresholds.disk_write_ops_per_second
      }
      network_in = {
        title     = "Network bytes received per second"
        type      = "compute.googleapis.com/instance/network/received_bytes_count"
        aligner   = "ALIGN_RATE"
        threshold = var.thresholds.network_received_mbit_per_second * 125000
      }
      uptime = {
        title     = "Uptime seconds per minute"
        type      = "compute.googleapis.com/instance/uptime"
        aligner   = "ALIGN_SUM"
        threshold = null
      }
    } :
    name => {
      title     = metric.title
      aligner   = metric.aligner
      threshold = metric.threshold
      filter = join(" ", compact([
        "metric.type=\"${metric.type}\"",
        "resource.type=\"gce_instance\"",
        "metadata.user_labels.application=\"${var.labels.application}\"",
        "metadata.user_labels.environment=\"${var.labels.environment}\"",
        try(metric.extra, ""),
      ]))
    }
  }
}

resource "google_project_iam_member" "metric_writer" {
  for_each = var.identities

  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = each.value
}

resource "google_monitoring_dashboard" "hosts" {
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = "${var.resource_prefix} hosts"
    mosaicLayout = {
      columns = 12
      tiles = [
        for name, metric in local.metrics : {
          xPos   = index(keys(local.metrics), name) % 2 * 6
          yPos   = floor(index(keys(local.metrics), name) / 2) * 4
          width  = 6
          height = 4
          widget = {
            title = metric.title
            xyChart = {
              dataSets = [{
                plotType = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = metric.filter
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = metric.aligner
                    }
                  }
                }
              }]
              thresholds = metric.threshold == null ? [] : [{ value = metric.threshold }]
              yAxis      = { scale = "LINEAR" }
            }
          }
        }
      ]
    }
  })
}
