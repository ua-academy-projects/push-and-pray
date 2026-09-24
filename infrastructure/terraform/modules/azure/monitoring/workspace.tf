resource "azurerm_log_analytics_workspace" "main" {
  count = local.workspace_enabled ? 1 : 0

  name                = "${local.resource_prefix}-logs"
  resource_group_name = var.network.resource_group_name
  location            = var.network.location
  sku                 = "PerGB2018"
  retention_in_days   = local.settings.log_retention_days
  tags                = local.common_tags
}

resource "azurerm_log_analytics_workspace_table_custom_log" "oilscope" {
  for_each = local.workspace_enabled ? { for key in local.active_streams : key => local.custom_streams[key] } : {}

  name         = each.value.table
  workspace_id = azurerm_log_analytics_workspace.main[0].id

  dynamic "column" {
    for_each = each.value.table_columns
    content {
      name = column.value.name
      type = column.value.type
    }
  }
}
