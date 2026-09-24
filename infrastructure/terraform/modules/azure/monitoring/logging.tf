resource "azurerm_monitor_data_collection_rule" "syslog" {
  for_each = local.locations

  name                = "${local.resource_prefix}-dcr-syslog${local.location_suffixes[each.key]}"
  resource_group_name = var.resource_group_names[each.key]
  location            = each.value.region
  kind                = "Linux"
  description         = "Warning and higher Linux system/service Syslog messages."
  tags                = local.labels

  destinations {
    log_analytics {
      name                  = "logs"
      workspace_resource_id = azurerm_log_analytics_workspace.logs[each.key].id
    }
  }

  data_sources {
    syslog {
      name           = "linux-syslog"
      facility_names = ["auth", "authpriv", "cron", "daemon", "kern", "syslog", "user"]
      log_levels     = ["Warning", "Error", "Critical", "Alert", "Emergency"]
      streams        = ["Microsoft-Syslog"]
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["logs"]
  }
}

resource "azurerm_monitor_data_collection_rule_association" "syslog" {
  for_each = var.vms

  name                    = "${local.resource_prefix}-syslog"
  target_resource_id      = each.value.resource_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.syslog[each.value.location].id
  description             = "Collect Linux Syslog into the regional Log Analytics workspace."

  depends_on = [azurerm_virtual_machine_extension.ama]
}
