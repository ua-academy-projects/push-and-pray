locals {
  enabled            = length(var.instances) > 0
  instance_locations = toset([for instance in values(var.instances) : instance.location])
  additional_workspace_locations = toset([
    for location in local.instance_locations : location
    if location != var.location
  ])
  synthetic_enabled = local.enabled && var.synthetic_monitoring_enabled && try(trimspace(var.public_endpoint_hostname), "") != ""
  log_destination   = "oilscope-log-analytics"
  dashboard_parts = merge(
    {
      "0" = {
        position = {
          x       = 0
          y       = 0
          colSpan = 12
          rowSpan = 2
        }
        metadata = {
          inputs = []
          type   = "Extension/HubsExtension/PartType/MarkdownPart"
          settings = {
            content = {
              settings = {
                content     = "# OilScope Azure monitoring\nCPU metrics, guest performance counters, syslog and HTTPS availability."
                title       = ""
                subtitle    = ""
                markdownUri = ""
              }
            }
          }
        }
      }
    },
    {
      for index, name in sort(keys(var.instances)) : tostring(index + 1) => {
        position = {
          x       = (index % 2) * 6
          y       = 2 + floor(index / 2) * 4
          colSpan = 6
          rowSpan = 4
        }
        metadata = {
          type = "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
          inputs = [
            {
              name = "options"
              value = {
                chart = {
                  metrics = [
                    {
                      resourceMetadata = {
                        id = var.instances[name].id
                      }
                      name            = "Percentage CPU"
                      aggregationType = 4
                      namespace       = "Microsoft.Compute/virtualMachines"
                      metricVisualization = {
                        displayName = "Percentage CPU"
                      }
                    }
                  ]
                  title = "${var.instances[name].name} CPU"
                  visualization = {
                    chartType = 2
                  }
                }
              }
            }
          ]
        }
      }
    }
  )
}

check "azure_monitoring_inputs" {
  assert {
    condition = (
      !local.enabled ||
      (var.resource_group_name != null && var.location != null && trimspace(var.notification_email) != "")
    )
    error_message = "Azure monitoring requires a resource group, location and notification email when Azure VMs exist."
  }
}

resource "azurerm_log_analytics_workspace" "this" {
  count = local.enabled ? 1 : 0

  name                = "${var.name_prefix}-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = merge(var.tags, { service = "monitoring" })
}

resource "azurerm_log_analytics_workspace" "regional" {
  for_each = local.enabled ? local.additional_workspace_locations : toset([])

  name                = "${var.name_prefix}-${replace(each.key, " ", "-")}-logs"
  location            = each.key
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = merge(var.tags, { service = "monitoring" })
}

resource "azurerm_monitor_action_group" "email" {
  count = local.enabled ? 1 : 0

  name                = "${var.name_prefix}-alerts"
  resource_group_name = var.resource_group_name
  short_name          = substr(replace(var.name_prefix, "-", ""), 0, 12)
  tags                = merge(var.tags, { service = "monitoring" })

  email_receiver {
    name                    = "operator-email"
    email_address           = var.notification_email
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_data_collection_rule" "linux" {
  for_each = local.enabled ? local.instance_locations : toset([])

  name                = "${var.name_prefix}-${replace(each.key, " ", "-")}-linux"
  resource_group_name = var.resource_group_name
  location            = each.key
  kind                = "Linux"
  tags                = merge(var.tags, { service = "monitoring" })

  destinations {
    log_analytics {
      workspace_resource_id = each.key == var.location ? azurerm_log_analytics_workspace.this[0].id : azurerm_log_analytics_workspace.regional[each.key].id
      name                  = local.log_destination
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Syslog"]
    destinations = [local.log_destination]
  }

  data_sources {
    performance_counter {
      name                          = "linux-performance"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\Processor Information(_Total)\\% Processor Time",
        "\\Memory\\% Used Memory",
        "\\Memory\\% Used Swap Space",
        "\\Logical Disk(*)\\% Used Space",
      ]
    }

    syslog {
      name           = "linux-syslog"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["*"]
      log_levels     = ["Warning", "Error", "Critical", "Alert", "Emergency"]
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "vm" {
  for_each = var.instances

  name                    = "${each.value.name}-linux-monitoring"
  target_resource_id      = each.value.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.linux[each.value.location].id
  description             = "Collect Linux guest metrics and syslog from ${each.value.name}."
}

resource "azurerm_monitor_metric_alert" "high_cpu" {
  for_each = var.instances

  name                = "${each.value.name}-high-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [each.value.id]
  description         = "Average CPU for ${each.value.name} is at least ${var.cpu_threshold}% for five minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true
  tags                = merge(var.tags, { service = "monitoring" })

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThanOrEqual"
    threshold        = var.cpu_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.email[0].id
  }
}

resource "azurerm_portal_dashboard" "infrastructure" {
  count = local.enabled ? 1 : 0

  name                = "${var.name_prefix}-dashboard"
  resource_group_name = var.resource_group_name
  location            = var.location
  dashboard_properties = jsonencode({
    lenses = {
      "0" = {
        order = 0
        parts = local.dashboard_parts
      }
    }
    metadata = {
      model = {
        timeRange = {
          value = {
            relative = {
              duration = 24
              timeUnit = 1
            }
          }
          type = "MsPortalFx.Composition.Configuration.ValueTypes.TimeRange"
        }
      }
    }
  })
  tags = merge(var.tags, {
    service        = "monitoring"
    "hidden-title" = "OilScope Azure Monitoring"
  })
}

resource "azurerm_application_insights" "this" {
  count = local.synthetic_enabled ? 1 : 0

  name                = "${var.name_prefix}-application-insights"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.this[0].id
  application_type    = "web"
  retention_in_days   = var.log_retention_days
  tags                = merge(var.tags, { service = "synthetic-monitoring" })
}

resource "azurerm_application_insights_standard_web_test" "https" {
  count = local.synthetic_enabled ? 1 : 0

  name                    = "${var.name_prefix}-https"
  resource_group_name     = var.resource_group_name
  location                = var.location
  application_insights_id = azurerm_application_insights.this[0].id
  description             = "Checks OilScope HTTPS and treats non-200 responses, including HTTP 500, as failures."
  enabled                 = true
  frequency               = 300
  timeout                 = 30
  retry_enabled           = true
  geo_locations = [
    "us-il-ch1-azr",
    "us-ca-sjc-azr",
    "us-tx-sn1-azr",
  ]
  tags = merge(var.tags, { service = "synthetic-monitoring" })

  request {
    url                              = "https://${var.public_endpoint_hostname}/"
    http_verb                        = "GET"
    follow_redirects_enabled         = true
    parse_dependent_requests_enabled = false
  }

  validation_rules {
    expected_status_code        = 200
    ssl_check_enabled           = true
    ssl_cert_remaining_lifetime = 7
  }
}

resource "azurerm_monitor_metric_alert" "https_failure" {
  count = local.synthetic_enabled ? 1 : 0

  name                = "${var.name_prefix}-https-failure"
  resource_group_name = var.resource_group_name
  scopes = [
    azurerm_application_insights_standard_web_test.https[0].id,
    azurerm_application_insights.this[0].id,
  ]
  description   = "OilScope returned a non-200 response or could not be reached from at least two test locations."
  severity      = 1
  frequency     = "PT1M"
  window_size   = "PT5M"
  auto_mitigate = true
  tags          = merge(var.tags, { service = "synthetic-monitoring" })

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.https[0].id
    component_id          = azurerm_application_insights.this[0].id
    failed_location_count = 2
  }

  action {
    action_group_id = azurerm_monitor_action_group.email[0].id
  }
}
