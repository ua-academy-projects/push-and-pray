resource "azurerm_monitor_metric_alert" "vm_cpu" {
  for_each = local.alarms_enabled ? local.workload_vms : {}

  name                = "${local.resource_prefix}-${each.key}-cpu"
  resource_group_name = var.network.resource_group_name
  scopes              = [each.value.instance_id]
  description         = "${each.key} CPU sustained above ${local.settings.cpu_threshold_percent}%."
  frequency           = "PT5M"
  window_size         = "PT5M"
  severity            = 2
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThanOrEqual"
    threshold        = local.settings.cpu_threshold_percent
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "database" {
  for_each = local.database_enabled && local.alarms_enabled ? local.database_signals : {}

  name                = "${local.resource_prefix}-database-${each.key}"
  resource_group_name = var.network.resource_group_name
  scopes              = [var.database.id]
  description         = "Managed PostgreSQL ${each.value.metric} above ${each.value.threshold}."
  frequency           = "PT5M"
  window_size         = "PT5M"
  severity            = 2
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = each.value.metric
    aggregation      = "Average"
    operator         = "GreaterThanOrEqual"
    threshold        = each.value.threshold
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

locals {
  guest_queries = local.agent_enabled ? merge([
    for name, vm in local.workload_vms : {
      for signal, definition in local.guest_signals : "${name}-${signal}" => {
        description = "${name} ${signal} sustained above ${definition.threshold}%."
        threshold   = definition.threshold
        operator    = "GreaterThanOrEqual"
        aggregation = "Maximum"
        column      = "Val"
        query       = <<-QUERY
          InsightsMetrics
          | where _ResourceId =~ "${vm.instance_id}"
          | where Namespace == "${definition.namespace}" and Name == "${definition.metric}"
        QUERY
      }
    }
  ]...) : {}

  absence_queries = merge(
    local.agent_enabled ? {
      for name, vm in local.workload_vms : "${name}-agent-missing" => {
        description = "${name} stopped reporting guest metrics; check the VM, the Azure Monitor Agent extension and its data collection rule association."
        threshold   = 0
        operator    = "LessThanOrEqual"
        aggregation = "Total"
        column      = "Rows"
        query       = <<-QUERY
          InsightsMetrics
          | where _ResourceId =~ "${vm.instance_id}"
          | summarize Rows = count()
        QUERY
      }
    } : {},
    local.application_enabled ? {
      for name, vm in local.workload_vms : "${name}-collector-missing" => {
        description = "${name} stopped publishing application measurements."
        threshold   = 0
        operator    = "LessThanOrEqual"
        aggregation = "Total"
        column      = "Rows"
        query       = <<-QUERY
          ${local.custom_streams.metrics.table}
          | where VMKey == "${name}"
          | summarize Rows = count()
        QUERY
      }
    } : {},
  )

  http_queries = local.logs_enabled ? {
    for key, predicate in local.http_filters : key => {
      description = "Traefik reported ${key} at or above the configured threshold."
      threshold   = local.settings.http_error_threshold
      operator    = "GreaterThanOrEqual"
      aggregation = "Total"
      column      = "Rows"
      query       = <<-QUERY
        ${local.custom_streams.access.table}
        | where ${predicate}
        | summarize Rows = count()
      QUERY
    }
  } : {}

  log_queries = merge(local.guest_queries, local.absence_queries, local.http_queries, local.application_queries)
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "logs" {
  for_each = local.alarms_enabled && local.workspace_enabled ? local.log_queries : {}

  name                = "${local.resource_prefix}-${each.key}"
  resource_group_name = var.network.resource_group_name
  location            = var.network.location
  scopes              = [azurerm_log_analytics_workspace.main[0].id]
  description         = each.value.description
  severity            = 2
  tags                = local.common_tags

  evaluation_frequency    = "PT5M"
  window_duration         = "PT10M"
  auto_mitigation_enabled = true
  skip_query_validation   = true

  criteria {
    query                   = each.value.query
    time_aggregation_method = each.value.aggregation
    metric_measure_column   = each.value.column
    threshold               = each.value.threshold
    operator                = each.value.operator

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = local.action_group_ids
  }

  depends_on = [azurerm_monitor_data_collection_rule.role]
}
