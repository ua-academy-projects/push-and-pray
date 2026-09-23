resource "azurerm_user_assigned_identity" "workload" {
  for_each = local.selected_vms

  name                = "${local.resource_prefix}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
}