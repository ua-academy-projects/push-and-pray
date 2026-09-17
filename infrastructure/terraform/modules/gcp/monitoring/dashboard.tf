locals {
  dashboard_vm_names = sort(keys(local.workload_vms))
  dashboard_signal_order = concat(
    ["cpu"],
    local.agent_enabled ? ["memory", "disk"] : []
  )
  dashboard_signal_titles = {
    cpu    = "VM CPU utilization"
    memory = "VM memory used (%)"
    disk   = "VM disk used (%)"
  }
  dashboard_charts = [for chart in concat(
    [for signal_name in local.dashboard_signal_order : {
      title = local.dashboard_signal_titles[signal_name]
      data_sets = [for name in local.dashboard_vm_names : {
        label   = name
        filter  = "${local.vm_filters[name]} AND metric.type=\"${local.signals[signal_name].metric}\"${local.signals[signal_name].extra}"
        aligner = local.signals[signal_name].aligner
        reducer = signal_name == "disk" ? "REDUCE_MAX" : null
      }]
    }],
    [{
      title = "VM uptime (seconds)"
      data_sets = [for name in local.dashboard_vm_names : {
        label   = name
        filter  = "${local.vm_filters[name]} AND metric.type=\"compute.googleapis.com/instance/uptime\""
        aligner = "ALIGN_MEAN"
        reducer = null
      }]
    }],
    [for direction in ["received", "sent"] : {
      title = "VM network ${direction} (bytes/s)"
      data_sets = [for name in local.dashboard_vm_names : {
        label   = name
        filter  = "${local.vm_filters[name]} AND metric.type=\"compute.googleapis.com/instance/network/${direction}_bytes_count\""
        aligner = "ALIGN_RATE"
        reducer = "REDUCE_SUM"
      }]
    }],
    local.application_enabled ? [for metric in keys(local.application_catalog) : {
      title     = metric
      data_sets = [for key, signal in local.application_signals : { label = signal.name, filter = local.application_filters[key], aligner = "ALIGN_MAX", reducer = null } if signal.metric == metric]
    } if anytrue([for signal in values(local.application_signals) : signal.metric == metric])] : [],
    local.database_enabled ? [for metric in ["database/cpu/utilization", "database/disk/utilization", "database/postgresql/num_backends", "database/disk/read_ops_count", "database/disk/write_ops_count"] : {
      title     = "Cloud SQL ${metric}"
      data_sets = [{ label = var.database.id, filter = "${local.database_filter} AND metric.type=\"cloudsql.googleapis.com/${metric}\"", aligner = endswith(metric, "_count") ? "ALIGN_RATE" : "ALIGN_MEAN", reducer = "REDUCE_SUM" }]
    }] : [],
    local.logs_enabled ? [{
      title = "HTTP errors (count/5 min)"
      data_sets = [for name, metric in google_logging_metric.http : {
        label   = name
        filter  = "resource.type=\"gce_instance\" AND metric.type=\"logging.googleapis.com/user/${metric.name}\""
        aligner = "ALIGN_SUM"
        reducer = "REDUCE_SUM"
      }]
    }] : []
  ) : chart if length(chart.data_sets) > 0]
}

resource "google_monitoring_dashboard" "operations" {
  count   = local.enabled && local.settings.dashboard_enabled ? 1 : 0
  project = local.project_id
  dashboard_json = jsonencode({
    displayName = "${local.resource_prefix} operations"
    gridLayout = {
      columns = 2
      widgets = concat([for chart in local.dashboard_charts : {
        title = chart.title
        xyChart = {
          dataSets = [for data_set in chart.data_sets : {
            legendTemplate = data_set.label
            plotType       = "LINE"
            targetAxis     = "Y1"
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = data_set.filter
                aggregation = merge({
                  alignmentPeriod  = "300s"
                  perSeriesAligner = data_set.aligner
                  }, data_set.reducer == null ? {} : {
                  crossSeriesReducer = data_set.reducer
                })
              }
            }
          }]
        }
        }], local.synthetics_enabled ? [{
        title = "HTTPS success fraction by checker"
        xyChart = {
          dataSets = [{
            legendTemplate = "${local.settings.synthetics.hostname}${local.settings.synthetics.path}"
            plotType       = "LINE"
            targetAxis     = "Y1"
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = local.uptime_filter
                aggregation = {
                  alignmentPeriod  = "${local.settings.synthetics.period_minutes * 60}s"
                  perSeriesAligner = "ALIGN_FRACTION_TRUE"
                }
              }
            }
          }]
        }
      }] : [])
    }
  })
  depends_on = [google_project_service.monitoring]
}
