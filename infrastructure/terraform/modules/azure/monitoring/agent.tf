resource "azurerm_monitor_data_collection_endpoint" "main" {
  count = local.agent_required ? 1 : 0

  name                = "${local.resource_prefix}-dce"
  resource_group_name = var.network.resource_group_name
  location            = var.network.location
  tags                = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "azurerm_monitor_data_collection_rule" "role" {
  for_each = local.agent_required ? local.role_log_sources : {}

  name                        = "${local.resource_prefix}-${each.key}"
  resource_group_name         = var.network.resource_group_name
  location                    = var.network.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.main[0].id
  tags                        = local.common_tags

  destinations {
    log_analytics {
      name                  = "logs"
      workspace_resource_id = azurerm_log_analytics_workspace.main[0].id
    }

    dynamic "azure_monitor_metrics" {
      for_each = local.agent_enabled ? [1] : []
      content {
        name = "metrics"
      }
    }
  }

  dynamic "stream_declaration" {
    for_each = each.value
    content {
      stream_name = "Custom-${local.custom_streams[stream_declaration.key].table}"

      dynamic "column" {
        for_each = local.custom_streams[stream_declaration.key].stream_columns
        content {
          name = column.value.name
          type = column.value.type
        }
      }
    }
  }

  data_sources {
    dynamic "performance_counter" {
      for_each = local.agent_enabled ? [1] : []
      content {
        name                          = "guest-metrics"
        streams                       = ["Microsoft-InsightsMetrics"]
        sampling_frequency_in_seconds = 60
        counter_specifiers = [
          "Processor(*)\\% Processor Time",
          "Memory(*)\\% Used Memory",
          "Memory(*)\\% Available Memory",
          "LogicalDisk(*)\\% Used Space",
          "LogicalDisk(*)\\% Free Space",
          "Network(*)\\Total Bytes Received",
          "Network(*)\\Total Bytes Transmitted",
        ]
      }
    }

    dynamic "log_file" {
      for_each = each.value
      content {
        name          = "oilscope-${log_file.key}"
        format        = local.custom_streams[log_file.key].format
        streams       = ["Custom-${local.custom_streams[log_file.key].table}"]
        file_patterns = log_file.value

        dynamic "settings" {
          for_each = local.custom_streams[log_file.key].format == "text" ? [1] : []
          content {
            text {
              record_start_timestamp_format = "ISO 8601"
            }
          }
        }
      }
    }
  }

  dynamic "data_flow" {
    for_each = local.agent_enabled ? [1] : []
    content {
      streams      = ["Microsoft-InsightsMetrics"]
      destinations = ["metrics", "logs"]
    }
  }

  dynamic "data_flow" {
    for_each = each.value
    content {
      streams       = ["Custom-${local.custom_streams[data_flow.key].table}"]
      destinations  = ["logs"]
      output_stream = "Custom-${local.custom_streams[data_flow.key].table}"
      transform_kql = local.custom_streams[data_flow.key].transform
    }
  }

  depends_on = [azurerm_log_analytics_workspace_table_custom_log.oilscope]
}

resource "azurerm_virtual_machine_extension" "monitor_agent" {
  for_each = local.agent_required ? local.workload_vms : {}

  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = each.value.instance_id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.33"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = local.common_tags

  settings = jsonencode({
    authentication = {
      managedIdentity = {
        "identifier-name"  = "mi_res_id"
        "identifier-value" = each.value.identity_resource_id
      }
    }
  })
}

resource "azurerm_monitor_data_collection_rule_association" "role" {
  for_each = local.agent_required ? local.workload_vms : {}

  name                    = "${local.resource_prefix}-${each.key}"
  target_resource_id      = each.value.instance_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.role[var.config.vms[each.key].role].id

  depends_on = [azurerm_virtual_machine_extension.monitor_agent]
}

locals {
  agent_configurations = {
    for name, vm in local.workload_vms : name => {
      vm_resource_id              = vm.instance_id
      identity_client_id          = vm.identity_client_id
      identity_resource_id        = vm.identity_resource_id
      extension_name              = azurerm_virtual_machine_extension.monitor_agent[name].name
      data_collection_rule_id     = azurerm_monitor_data_collection_rule.role[var.config.vms[name].role].id
      data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.main[0].id
      association_name            = azurerm_monitor_data_collection_rule_association.role[name].name
      log_directory               = local.log_directory
      log_sources                 = local.role_log_sources[var.config.vms[name].role]
      ownership                   = "terraform"
    } if local.agent_required
  }
}
