output "virtual_network_id" {
  value = azurerm_virtual_network.main.id
}

output "management_subnet_id" {
  value = azurerm_subnet.management.id
}

output "workload_subnet_id" {
  value = azurerm_subnet.workload.id
}

output "managed_database_subnet_id" {
  value = try(azurerm_subnet.managed_database[0].id, null)
}

output "managed_database_private_dns_zone_id" {
  value = try(azurerm_private_dns_zone.postgres[0].id, null)
}
