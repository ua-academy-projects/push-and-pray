resource "azurerm_log_analytics_workspace" "this" {
  for_each = local.shared_resources

  name                = "${local.resource_prefix}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.config.monitoring.azure.log_retention_days
  daily_quota_gb      = var.config.monitoring.azure.daily_ingestion_limit_gb
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  for_each = local.shared_resources

  name                = "${local.resource_prefix}-appinsights"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.this[each.key].id
  application_type    = "web"
  tags                = local.tags
}

resource "azurerm_monitor_action_group" "this" {
  for_each = local.enabled && try(var.config.monitoring.azure.notification_email, null) != null ? {
    main = var.config.monitoring.azure.notification_email
  } : {}

  name                = "${local.resource_prefix}-alerts"
  resource_group_name = var.resource_group_name
  short_name          = substr("${var.config.name_prefix}-${var.config.environment}", 0, 12)
  tags                = local.tags

  email_receiver {
    name                    = "operator"
    email_address           = each.value
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_data_collection_rule" "host" {
  for_each = local.shared_resources

  name                = "${local.resource_prefix}-host-dcr"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "Linux"
  description         = "OilScope Linux host performance and system log collection."
  tags                = local.tags

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.this[each.key].id
      name                  = "workspace"
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Syslog"]
    destinations = ["workspace"]
  }

  data_sources {
    performance_counter {
      name                          = "host-performance"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\Processor(*)\\% Processor Time",
        "\\Memory\\% Used Memory",
        "\\Logical Disk(*)\\% Used Space",
        "\\Logical Disk(*)\\Disk Reads/sec",
        "\\Logical Disk(*)\\Disk Writes/sec",
        "\\Network(*)\\Total Bytes Received",
        "\\Network(*)\\Total Bytes Transmitted",
      ]
    }

    syslog {
      name           = "system-logs"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["auth", "authpriv", "daemon", "syslog", "user", "local0"]
      log_levels     = ["Info", "Notice", "Warning", "Error", "Critical", "Alert", "Emergency"]
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "host" {
  for_each = local.azure_instance_ids

  name                    = "${local.resource_prefix}-host"
  target_resource_id      = each.value
  data_collection_rule_id = azurerm_monitor_data_collection_rule.host["main"].id
  description             = "Collect OilScope host metrics and logs from ${each.key}."
}

resource "azurerm_monitor_metric_alert" "cpu" {
  for_each = local.azure_instance_ids

  name                = "${local.resource_prefix}-${each.key}-high-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [each.value]
  description         = "CPU utilization is above 80 percent on ${each.key}."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  auto_mitigate       = true
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "availability" {
  for_each = local.azure_instance_ids

  name                = "${local.resource_prefix}-${each.key}-unavailable"
  resource_group_name = var.resource_group_name
  scopes              = [each.value]
  description         = "Azure reports ${each.key} as unavailable."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true
  tags                = local.tags

  criteria {
    metric_namespace       = "Microsoft.Compute/virtualMachines"
    metric_name            = "VmAvailabilityMetric"
    aggregation            = "Minimum"
    operator               = "LessThan"
    threshold              = 1
    skip_metric_validation = true
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "memory" {
  for_each = local.shared_resources

  name                  = "${local.resource_prefix}-high-memory"
  resource_group_name   = var.resource_group_name
  location              = var.location
  scopes                = [azurerm_log_analytics_workspace.this[each.key].id]
  description           = "Memory utilization is above 80 percent on an OilScope VM."
  severity              = 2
  evaluation_frequency  = "PT5M"
  window_duration       = "PT15M"
  enabled               = true
  skip_query_validation = true
  tags                  = local.tags

  criteria {
    query                   = <<-KQL
      Perf
      | where ObjectName == "Memory" and CounterName == "% Used Memory"
      | summarize AggregatedValue=max(CounterValue) by bin(TimeGenerated, 5m), Computer
    KQL
    metric_measure_column   = "AggregatedValue"
    time_aggregation_method = "Maximum"
    operator                = "GreaterThan"
    threshold               = 80

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 3
      number_of_evaluation_periods             = 3
    }
  }

  dynamic "action" {
    for_each = length(local.action_group_ids) == 0 ? [] : [local.action_group_ids]
    content {
      action_groups = action.value
    }
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "disk" {
  for_each = local.shared_resources

  name                  = "${local.resource_prefix}-high-disk-usage"
  resource_group_name   = var.resource_group_name
  location              = var.location
  scopes                = [azurerm_log_analytics_workspace.this[each.key].id]
  description           = "Root filesystem utilization is above 80 percent on an OilScope VM."
  severity              = 2
  evaluation_frequency  = "PT5M"
  window_duration       = "PT15M"
  enabled               = true
  skip_query_validation = true
  tags                  = local.tags

  criteria {
    query                   = <<-KQL
      Perf
      | where ObjectName == "Logical Disk" and CounterName == "% Used Space" and InstanceName == "/"
      | summarize AggregatedValue=max(CounterValue) by bin(TimeGenerated, 5m), Computer
    KQL
    metric_measure_column   = "AggregatedValue"
    time_aggregation_method = "Maximum"
    operator                = "GreaterThan"
    threshold               = 80

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 3
      number_of_evaluation_periods             = 3
    }
  }

  dynamic "action" {
    for_each = length(local.action_group_ids) == 0 ? [] : [local.action_group_ids]
    content {
      action_groups = action.value
    }
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "heartbeat" {
  for_each = local.shared_resources

  name                  = "${local.resource_prefix}-agent-heartbeat-missing"
  resource_group_name   = var.resource_group_name
  location              = var.location
  scopes                = [azurerm_log_analytics_workspace.this[each.key].id]
  description           = "An OilScope VM has not sent an Azure Monitor Agent heartbeat for ten minutes."
  severity              = 1
  evaluation_frequency  = "PT5M"
  window_duration       = "PT10M"
  enabled               = true
  skip_query_validation = true
  tags                  = local.tags

  criteria {
    query                   = <<-KQL
      let expected = datatable(ResourceId:string)[${local.expected_resource_ids}];
      expected
      | join kind=leftanti (
          Heartbeat
          | where TimeGenerated > ago(10m)
          | summarize by ResourceId=tolower(_ResourceId)
        ) on ResourceId
      | project TimeGenerated=now(), ResourceId
    KQL
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  dynamic "action" {
    for_each = length(local.action_group_ids) == 0 ? [] : [local.action_group_ids]
    content {
      action_groups = action.value
    }
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "http_5xx" {
  for_each = length(local.azure_ui) == 0 ? {} : local.shared_resources

  name                  = "${local.resource_prefix}-http-5xx"
  resource_group_name   = var.resource_group_name
  location              = var.location
  scopes                = [azurerm_log_analytics_workspace.this[each.key].id]
  description           = "Traefik returned one or more HTTP 5xx responses within five minutes."
  severity              = 1
  evaluation_frequency  = "PT5M"
  window_duration       = "PT5M"
  enabled               = true
  skip_query_validation = true
  tags                  = local.tags

  criteria {
    query                   = <<-KQL
      Syslog
      | where Facility == "local0" and SyslogMessage matches regex @"DownstreamStatus[^0-9]*5[0-9]{2}[^0-9]"
    KQL
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  dynamic "action" {
    for_each = length(local.action_group_ids) == 0 ? [] : [local.action_group_ids]
    content {
      action_groups = action.value
    }
  }
}

resource "azurerm_application_insights_standard_web_test" "https" {
  for_each = local.azure_ui

  name                    = "${local.resource_prefix}-https-availability"
  resource_group_name     = var.resource_group_name
  location                = var.location
  application_insights_id = azurerm_application_insights.this["main"].id
  geo_locations           = ["emea-nl-ams-azr"]
  frequency               = 900
  timeout                 = 30
  enabled                 = true
  retry_enabled           = true
  description             = "OilScope public HTTPS health check."
  tags                    = local.tags

  request {
    url                              = "https://${each.value.public_endpoint.hostname}/health"
    http_verb                        = "GET"
    parse_dependent_requests_enabled = false
  }

  validation_rules {
    expected_status_code        = 200
    ssl_check_enabled           = true
    ssl_cert_remaining_lifetime = 7
  }
}

resource "azurerm_monitor_metric_alert" "https" {
  for_each = local.azure_ui

  name                = "${local.resource_prefix}-https-unavailable"
  resource_group_name = var.resource_group_name
  scopes = [
    azurerm_application_insights_standard_web_test.https[each.key].id,
    azurerm_application_insights.this["main"].id,
  ]
  description   = "The public OilScope HTTPS health endpoint is unavailable."
  severity      = 1
  frequency     = "PT5M"
  window_size   = "PT15M"
  auto_mitigate = true
  tags          = local.tags

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.https[each.key].id
    component_id          = azurerm_application_insights.this["main"].id
    failed_location_count = 1
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_application_insights_workbook" "this" {
  for_each = local.shared_resources

  name                = uuidv5("dns", "${var.config.cloud_settings.azure.subscription_id}/${local.resource_prefix}/observability")
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "OilScope"
  description         = "OilScope host, application, and availability monitoring."
  tags                = local.tags

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = concat(
      [{
        type = 1
        name = "overview"
        content = {
          json = "# OilScope monitoring\nHost metrics include the bastion and every workload VM. Application log panels include workload VMs only."
        }
      }],
      [for index, panel in slice(local.workbook_queries, 0, 1) : {
        type = 3
        name = "query-${index}"
        content = merge({
          version      = "KqlItem/1.0"
          title        = panel.title
          query        = panel.query
          size         = 0
          aggregation  = panel.aggregation
          queryType    = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          crossComponentResources = [
            azurerm_log_analytics_workspace.this[each.key].id,
          ]
          visualization = panel.visualization
          }, panel.chart_settings == null ? {} : {
          chartSettings = panel.chart_settings
        })
      }],
      [for index, panel in local.workbook_metric_panels : {
        type = 10
        name = "metric-${index}"
        content = {
          version      = "MetricsItem/2.0"
          chartId      = uuidv5("dns", "${var.config.cloud_settings.azure.subscription_id}/${local.resource_prefix}/observability/${panel.metric}")
          title        = panel.title
          size         = 0
          chartType    = 2
          metricScope  = 0
          resourceType = "microsoft.compute/virtualmachines"
          resourceIds  = values(local.azure_instance_ids)
          timeContext = {
            durationMs = 21600000
          }
          metrics = [{
            namespace   = "microsoft.compute/virtualmachines"
            metric      = "microsoft.compute/virtualmachines--${panel.metric}"
            aggregation = 4
          }]
        }
      }],
      [for index, panel in slice(local.workbook_queries, 1, length(local.workbook_queries)) : {
        type = 3
        name = "query-${index + 1}"
        content = merge({
          version      = "KqlItem/1.0"
          title        = panel.title
          query        = panel.query
          size         = 0
          aggregation  = panel.aggregation
          queryType    = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          crossComponentResources = [
            azurerm_log_analytics_workspace.this[each.key].id,
          ]
          visualization = panel.visualization
          }, panel.chart_settings == null ? {} : {
          chartSettings = panel.chart_settings
        })
      }],
    )
    isLocked = false
    fallbackResourceIds = [
      azurerm_log_analytics_workspace.this[each.key].id,
      azurerm_application_insights.this[each.key].id,
    ]
  })
}
