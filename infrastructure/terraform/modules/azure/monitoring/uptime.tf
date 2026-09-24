resource "azurerm_application_insights" "health" {
  count = local.synthetics_enabled ? 1 : 0

  name                = "${local.resource_prefix}-health"
  resource_group_name = var.network.resource_group_name
  location            = var.network.location
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  tags                = local.common_tags
}

resource "azurerm_application_insights_standard_web_test" "health" {
  count = local.synthetics_enabled ? 1 : 0

  name                    = "${local.resource_prefix}-health"
  resource_group_name     = var.network.resource_group_name
  location                = var.network.location
  application_insights_id = azurerm_application_insights.health[0].id
  frequency               = local.settings.synthetics.period_minutes * 60
  timeout                 = 30
  enabled                 = true
  retry_enabled           = true
  geo_locations           = ["emea-nl-ams-azr", "emea-gb-db3-azr", "emea-fr-pra-edge"]
  tags                    = local.common_tags

  request {
    url = "https://${local.settings.synthetics.hostname}${local.settings.synthetics.path}"
  }

  validation_rules {
    expected_status_code = 200
    ssl_check_enabled    = true

    content {
      content_match      = "ok"
      ignore_case        = true
      pass_if_text_found = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "health" {
  count = local.alarms_enabled && local.synthetics_enabled ? 1 : 0

  name                = "${local.resource_prefix}-health"
  resource_group_name = var.network.resource_group_name
  scopes = [
    azurerm_application_insights_standard_web_test.health[0].id,
    azurerm_application_insights.health[0].id,
  ]
  description = "The public health endpoint failed from more than one location."
  frequency   = "PT5M"
  window_size = "PT5M"
  severity    = 1
  tags        = local.common_tags

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.health[0].id
    component_id          = azurerm_application_insights.health[0].id
    failed_location_count = 2
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
