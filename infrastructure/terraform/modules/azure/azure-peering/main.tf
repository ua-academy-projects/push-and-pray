resource "azurerm_virtual_network_peering" "primary_to_region" {
  for_each = var.peer_regions

  name                      = "${var.config.name_prefix}-${var.config.environment}-${var.primary_region_key}-to-${each.key}"
  resource_group_name       = var.resource_group_names[var.primary_region_key]
  virtual_network_name      = var.virtual_network_names[var.primary_region_key]
  remote_virtual_network_id = var.virtual_network_ids[each.key]

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "region_to_primary" {
  for_each = var.peer_regions

  name                      = "${var.config.name_prefix}-${var.config.environment}-${each.key}-to-${var.primary_region_key}"
  resource_group_name       = var.resource_group_names[each.key]
  virtual_network_name      = var.virtual_network_names[each.key]
  remote_virtual_network_id = var.virtual_network_ids[var.primary_region_key]

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}
