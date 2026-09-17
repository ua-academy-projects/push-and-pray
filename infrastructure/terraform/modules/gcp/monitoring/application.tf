locals {
  application_catalog = jsondecode(file("${path.module}/../../../monitoring-metrics.json"))
  application_signals = merge({}, [for name, vm in local.workload_vms : {
    for metric, definition in local.application_catalog : "${name}-${metric}" => {
      name      = name
      metric    = metric
      threshold = try(local.settings[definition.setting], definition.threshold)
    } if contains(definition.roles, var.config.vms[name].role)
  }]...)
  collector_configurations = { for name, vm in local.workload_vms : name => {
    cloud       = "gcp"
    vm_key      = name
    namespace   = local.application_namespace
    instance_id = vm.instance_id
    project_id  = local.project_id
    zone        = vm.zone
    environment = var.config.environment
    name_prefix = var.config.name_prefix
  } if local.application_enabled }
}
output "collector_configurations" {
  value = local.collector_configurations
}
resource "google_monitoring_metric_descriptor" "application" {
  for_each     = { for key, definition in local.application_catalog : key => definition if local.application_enabled }
  project      = local.project_id
  type         = "custom.googleapis.com/${var.config.name_prefix}/${var.config.environment}/${each.key}"
  metric_kind  = "GAUGE"
  value_type   = "DOUBLE"
  unit         = each.value.unit == "Seconds" ? "s" : (each.value.unit == "Percent" ? "%" : "1")
  display_name = "${local.resource_prefix} ${each.key}"
  depends_on   = [google_project_service.monitoring]
}
locals {
  application_filters = { for key, signal in local.application_signals : key => "${local.vm_filters[signal.name]} AND metric.type=\"custom.googleapis.com/${var.config.name_prefix}/${var.config.environment}/${signal.metric}\"" }
  database_signals = {
    cpu         = { metric = "database/cpu/utilization", threshold = local.settings.database_cpu_threshold_percent / 100 }
    disk        = { metric = "database/disk/utilization", threshold = local.settings.database_disk_threshold_percent / 100 }
    connections = { metric = "database/postgresql/num_backends", threshold = local.settings.database_connections_threshold }
  }
  database_filter = "resource.type=\"cloudsql_database\" AND resource.labels.database_id=\"${try(var.database.id, "disabled")}\""
  extra_signals = merge(
    local.application_enabled ? { for key, signal in local.application_signals : key => { filter = local.application_filters[key], threshold = signal.threshold } } : {},
    local.database_enabled ? { for key, signal in local.database_signals : "database-${key}" => { filter = "${local.database_filter} AND metric.type=\"cloudsql.googleapis.com/${signal.metric}\"", threshold = signal.threshold } } : {}
  )
}
resource "google_monitoring_alert_policy" "application_database" {
  for_each              = local.alarms_enabled ? local.extra_signals : {}
  project               = local.project_id
  display_name          = "${local.resource_prefix}-${each.key}"
  combiner              = "OR"
  notification_channels = local.notification_channels
  conditions {
    display_name = "${each.key} threshold"
    condition_threshold {
      filter                  = each.value.filter
      comparison              = "COMPARISON_GT"
      threshold_value         = each.value.threshold * 0.999999
      duration                = "300s"
      evaluation_missing_data = "EVALUATION_MISSING_DATA_ACTIVE"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_MAX"
        cross_series_reducer = "REDUCE_SUM"
      }
      trigger { count = 1 }
    }
  }
  depends_on = [google_monitoring_metric_descriptor.application, google_project_service.monitoring]
}
resource "google_monitoring_alert_policy" "collector_missing" {
  for_each              = local.application_enabled && local.alarms_enabled ? local.workload_vms : {}
  project               = local.project_id
  display_name          = "${local.resource_prefix}-${each.key}-collector-missing"
  combiner              = "OR"
  notification_channels = local.notification_channels
  conditions {
    display_name = "Collector stopped reporting"
    condition_absent {
      filter   = local.application_filters["${each.key}-CollectionFailed"]
      duration = "600s"
      trigger { count = 1 }
    }
  }
  depends_on = [google_monitoring_metric_descriptor.application]
}
