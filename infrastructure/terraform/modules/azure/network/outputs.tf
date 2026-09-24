output "resource_group_names" {
  value = { for location, group in azurerm_resource_group.main : location => group.name }
}

output "management_subnet_ids" {
  value      = { for location, subnet in azurerm_subnet.management : location => subnet.id }
  depends_on = [azurerm_subnet_nat_gateway_association.management, azurerm_nat_gateway_public_ip_association.main]
}

output "workload_subnet_ids" {
  value      = { for location, subnet in azurerm_subnet.workload : location => subnet.id }
  depends_on = [azurerm_subnet_nat_gateway_association.workload, azurerm_nat_gateway_public_ip_association.main]
}

output "network_security_group_ids" {
  value = { for name, group in azurerm_network_security_group.vm : name => group.id }
}

output "default_resource_group_name" {
  value = try(azurerm_resource_group.main[var.config.default_location].name, null)
}

output "database_subnet_id" {
  value      = try(azurerm_subnet.database[0].id, null)
  depends_on = [azurerm_subnet_network_security_group_association.database]
}

output "database_private_dns_zone_id" {
  value      = try(azurerm_private_dns_zone.database[0].id, null)
  depends_on = [azurerm_private_dns_zone_virtual_network_link.database]
}
