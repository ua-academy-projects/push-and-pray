resource "azurerm_monitor_workspace" "metrics" {
  for_each = local.locations

  name                = "${local.resource_prefix}-amw${local.location_suffixes[each.key]}"
  resource_group_name = var.resource_group_names[each.key]
  location            = each.value.region
  tags                = local.labels
}

resource "azurerm_log_analytics_workspace" "logs" {
  for_each = local.locations

  name                = "${local.resource_prefix}-law${local.location_suffixes[each.key]}"
  resource_group_name = var.resource_group_names[each.key]
  location            = each.value.region
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.labels
}

resource "azurerm_virtual_machine_extension" "ama" {
  for_each = var.vms

  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = each.value.resource_id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.38"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = local.labels

  # The VM module enables the system-assigned identity used by AMA by default.
  # 1.38 introduced Linux OpenTelemetry support; automatic upgrades stay enabled.
}
