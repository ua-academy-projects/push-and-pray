locals {
  application_catalog = jsondecode(file("${path.module}/../../../monitoring-metrics.json"))
  application_signals = merge({}, [for name, vm in local.workload_vms : {
    for metric, definition in local.application_catalog : "${name}-${metric}" => {
      name      = name
      metric    = metric
      threshold = try(local.settings[definition.setting], definition.threshold)
    } if contains(definition.roles, var.config.vms[name].role)
  }]...)

  application_queries = local.application_enabled ? {
    for key, signal in local.application_signals : key => {
      description = "${signal.name} reported ${signal.metric} at or above ${signal.threshold}."
      threshold   = signal.threshold
      operator    = "GreaterThanOrEqual"
      aggregation = "Maximum"
      column      = "Value"
      query       = <<-QUERY
        ${local.custom_streams.metrics.table}
        | where VMKey == "${signal.name}" and Metric == "${signal.metric}"
      QUERY
    }
  } : {}

  collector_configurations = { for name, vm in local.workload_vms : name => {
    cloud          = "azure"
    vm_key         = name
    resource_id    = vm.instance_id
    destination    = "${local.log_directory}/application-metrics.jsonl"
    schema_version = 1
    fields         = [for column in local.custom_streams.metrics.stream_columns : column.name]
  } if local.application_enabled }
}

output "collector_configurations" {
  value = local.collector_configurations
}
