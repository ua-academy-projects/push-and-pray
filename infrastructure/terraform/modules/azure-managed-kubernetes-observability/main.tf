resource "azurerm_monitor_data_collection_rule" "container_insights" {
  name                = "MSCI-${var.cluster.name}-${var.cluster.location}"
  resource_group_name = var.cluster.resource_group_name
  location            = var.cluster.location
  description         = "Container Insights inventory, performance, event, and container-log collection for ${var.cluster.name}."
  tags                = local.tags

  destinations {
    log_analytics {
      name                  = "container-insights"
      workspace_resource_id = var.workspace_id
    }
  }

  data_flow {
    streams      = ["Microsoft-ContainerInsights-Group-Default"]
    destinations = ["container-insights"]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = ["Microsoft-ContainerInsights-Group-Default"]
      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "1m"
          namespaceFilteringMode = "Off"
          namespaces             = []
          enableContainerLogV2   = true
        }
      })
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "container_insights" {
  name                    = "ContainerInsightsExtension"
  target_resource_id      = var.cluster.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights.id
  description             = "Associates the AKS cluster with its Container Insights data collection rule."
}

resource "azurerm_monitor_metric_alert" "node" {
  for_each = local.node_metric_alerts

  name                = each.value.name
  resource_group_name = var.cluster.resource_group_name
  scopes              = [var.cluster.id]
  description         = each.value.description
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  auto_mitigate       = true
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = each.value.metric
    aggregation      = each.value.aggregation
    operator         = "GreaterThan"
    threshold        = each.value.threshold

    dynamic "dimension" {
      for_each = each.value.dimensions
      content {
        name     = dimension.value.name
        operator = "Include"
        values   = dimension.value.values
      }
    }
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "log" {
  for_each = local.log_alerts

  name                    = each.value.name
  resource_group_name     = var.cluster.resource_group_name
  location                = var.cluster.location
  scopes                  = [var.workspace_id]
  description             = each.value.description
  severity                = each.value.severity
  evaluation_frequency    = "PT5M"
  window_duration         = "PT10M"
  enabled                 = true
  auto_mitigation_enabled = true
  skip_query_validation   = true
  tags                    = local.tags

  criteria {
    query                   = each.value.query
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 2
      number_of_evaluation_periods             = 2
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
  name                    = "${local.resource_prefix}-aks-https-availability"
  resource_group_name     = var.cluster.resource_group_name
  location                = var.cluster.location
  application_insights_id = var.application_insights_id
  geo_locations           = ["emea-nl-ams-azr"]
  frequency               = 300
  timeout                 = 30
  enabled                 = true
  retry_enabled           = true
  description             = "OilScope AKS public HTTPS health check."
  tags                    = local.tags

  request {
    url                              = "https://${local.application_host}/health"
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
  name                = "${local.resource_prefix}-aks-https-unavailable"
  resource_group_name = var.cluster.resource_group_name
  scopes = [
    azurerm_application_insights_standard_web_test.https.id,
    var.application_insights_id,
  ]
  description   = "The public OilScope AKS HTTPS health endpoint is unavailable."
  severity      = 1
  frequency     = "PT5M"
  window_size   = "PT15M"
  auto_mitigate = true
  tags          = local.tags

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.https.id
    component_id          = var.application_insights_id
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
  name                = uuidv5("dns", "${var.config.cloud_settings.azure.subscription_id}/${local.resource_prefix}/aks-observability")
  resource_group_name = var.cluster.resource_group_name
  location            = var.cluster.location
  display_name        = "OilScope AKS"
  description         = "OilScope AKS cluster, node, pod, container, and availability monitoring."
  tags                = local.tags

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = concat(
      [{
        type = 1
        name = "overview"
        content = {
          json = "# OilScope AKS monitoring\nAzure Monitor Container Insights for ${var.cluster.name}. Metrics and logs can take approximately ten minutes to appear after onboarding."
        }
      }],
      [for index, panel in local.workbook_queries : {
        type = 3
        name = "query-${index}"
        content = {
          version      = "KqlItem/1.0"
          title        = panel.title
          query        = panel.query
          size         = 0
          aggregation  = 3
          queryType    = 0
          resourceType = "microsoft.operationalinsights/workspaces"
          crossComponentResources = [
            var.workspace_id,
          ]
          visualization = panel.visualization
        }
      }],
    )
    isLocked = false
    fallbackResourceIds = [
      var.workspace_id,
      var.application_insights_id,
      var.cluster.id,
    ]
  })
}
