resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.resource_prefix}-logs"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  # This tier keeps data for 30 to 730 days.
  retention_in_days = min(max(var.retention_days, 30), 730)

  tags = var.tags
}

# What the agent collects is a resource in the cloud, not a file on the host:
# the journal, as rsyslog receives it from journald, and the one host counter
# the platform metrics lack - memory in use.
resource "azurerm_monitor_data_collection_rule" "hosts" {
  name                = "${var.resource_prefix}-hosts"
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"

  destinations {
    log_analytics {
      name                  = "workspace"
      workspace_resource_id = azurerm_log_analytics_workspace.main.id
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog", "Microsoft-Perf"]
    destinations = ["workspace"]
  }

  data_sources {
    syslog {
      name           = "journal"
      facility_names = ["*"]
      log_levels     = ["*"]
      streams        = ["Microsoft-Syslog"]
    }

    performance_counter {
      name                          = "memory"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers            = ["Memory(*)\\Used Memory MBytes"]
    }
  }

  tags = var.tags
}

# The Azure Monitor Agent exists only as a VM extension, so it is installed
# here rather than by Ansible as on the other clouds. It authenticates as the
# VM's own user-assigned identity; left to choose, it would ask Azure to add a
# system-assigned one, and a second identity makes the metadata service
# ambiguous for resolve_secrets.
resource "azurerm_virtual_machine_extension" "agent" {
  for_each = var.instances

  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = each.value.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true

  settings = jsonencode({
    authentication = {
      managedIdentity = {
        identifier-name  = "mi_res_id"
        identifier-value = each.value.identity_id
      }
    }
  })

  tags = var.tags
}

# The association is what grants the agent the right to send: no role on the
# workspace is needed, where GCP and AWS each grant a writer role.
resource "azurerm_monitor_data_collection_rule_association" "hosts" {
  for_each = var.instances

  name                    = "${var.resource_prefix}-${each.key}-hosts"
  target_resource_id      = each.value.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.hosts.id
}
