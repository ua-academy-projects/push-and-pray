resource "azurerm_resource_group" "main" {
  count = var.has_selected_vms ? 1 : 0

  name     = "${local.resource_prefix}-rg"
  location = local.location
}