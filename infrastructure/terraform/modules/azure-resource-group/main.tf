resource "azurerm_resource_group" "this" {
  for_each = local.resource_groups

  name     = "${local.resource_prefix}-rg"
  location = each.value
  tags     = local.tags
}
