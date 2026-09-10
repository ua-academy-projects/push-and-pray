locals {
  charts = concat([for key, signal in local.vm_signals : { title = key, filter = signal.filter, aligner = signal.aligner }],
    [for name, vm in var.vms : { title = "${name} VM uptime", filter = "${local.vm_filters[name]} AND metric.type=\"compute.googleapis.com/instance/uptime\"", aligner = "ALIGN_MEAN" }],
    flatten([for name, vm in var.vms : [for direction in ["received", "sent"] : { title = "${name} network ${direction} bytes/s", filter = "${local.vm_filters[name]} AND metric.type=\"compute.googleapis.com/instance/network/${direction}_bytes_count\"", aligner = "ALIGN_RATE" }]]),
  [for name, metric in google_logging_metric.http : { title = name, filter = "resource.type=\"gce_instance\" AND metric.type=\"logging.googleapis.com/user/${metric.name}\"", aligner = "ALIGN_SUM" }])
}
resource "google_monitoring_dashboard" "operations" {
  count   = local.enabled && local.settings.dashboard_enabled ? 1 : 0
  project = local.project_id
  dashboard_json = jsonencode({
    displayName = "${local.resource_prefix} operations"
    gridLayout = { columns = 2, widgets = concat([for chart in local.charts : {
      title   = chart.title
      xyChart = { dataSets = [{ plotType = "LINE", timeSeriesQuery = { timeSeriesFilter = { filter = chart.filter, aggregation = { alignmentPeriod = "300s", perSeriesAligner = chart.aligner } } } }] }
      }], local.synthetics_enabled ? [{
      title   = "HTTPS success fraction by checker"
      xyChart = { dataSets = [{ plotType = "LINE", timeSeriesQuery = { timeSeriesFilter = { filter = local.uptime_filter, aggregation = { alignmentPeriod = "${local.settings.synthetics.period_minutes * 60}s", perSeriesAligner = "ALIGN_FRACTION_TRUE" } } } }] }
    }] : []) }
  })
  depends_on = [google_project_service.monitoring]
}
