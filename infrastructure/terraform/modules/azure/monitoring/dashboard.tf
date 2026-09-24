locals {
  dashboard_vm_filter = length(local.workload_vms) > 0 ? join(", ", [
    for vm in values(local.workload_vms) : "\"${vm.instance_id}\""
  ]) : "\"\""

  dashboard_charts = concat(
    local.agent_enabled ? [
      for signal, definition in local.guest_signals : {
        title = "VM ${definition.metric}"
        query = <<-QUERY
          InsightsMetrics
          | where _ResourceId in~ (${local.dashboard_vm_filter})
          | where Namespace == "${definition.namespace}" and Name == "${definition.metric}"
          | summarize avg(Val) by bin(TimeGenerated, 5m), Computer
          | render timechart
        QUERY
      }
    ] : [],
    local.agent_enabled ? [{
      title = "VM CPU (% processor time)"
      query = <<-QUERY
        InsightsMetrics
        | where _ResourceId in~ (${local.dashboard_vm_filter})
        | where Namespace == "Processor" and Name == "% Processor Time"
        | summarize avg(Val) by bin(TimeGenerated, 5m), Computer
        | render timechart
      QUERY
    }] : [],
    local.logs_enabled ? [{
      title = "HTTP responses by status"
      query = <<-QUERY
        ${local.custom_streams.access.table}
        | summarize count() by bin(TimeGenerated, 5m), tostring(DownstreamStatus)
        | render timechart
      QUERY
    }] : [],
    local.application_enabled ? [
      for metric in sort(keys(local.application_catalog)) : {
        title = metric
        query = <<-QUERY
          ${local.custom_streams.metrics.table}
          | where Metric == "${metric}"
          | summarize max(Value) by bin(TimeGenerated, 5m), VMKey
          | render timechart
        QUERY
      }
    ] : [],
    local.service_logs_enabled ? [{
      title = "Service log volume by file"
      query = <<-QUERY
        ${local.custom_streams.service.table}
        | summarize count() by bin(TimeGenerated, 5m), FilePath
        | render timechart
      QUERY
    }] : [],
  )
}

resource "azurerm_application_insights_workbook" "operations" {
  count = local.workspace_enabled && local.settings.dashboard_enabled && length(local.dashboard_charts) > 0 ? 1 : 0

  name                = uuidv5("url", "https://oilscope.invalid/${local.resource_prefix}/operations")
  resource_group_name = var.network.resource_group_name
  location            = var.network.location
  display_name        = "${local.resource_prefix} operations"
  source_id           = lower(azurerm_log_analytics_workspace.main[0].id)
  tags                = local.common_tags

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      for index, chart in local.dashboard_charts : {
        type = 3
        name = "chart-${index}"
        content = {
          version      = "KqlItem/1.0"
          query        = chart.query
          size         = 0
          title        = chart.title
          queryType    = 0
          resourceType = "microsoft.operationalinsights/workspaces"
        }
      }
    ]
  })
}
