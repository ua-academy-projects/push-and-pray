output "vnet_id" {
  value = try(azurerm_virtual_network.main[0].id, null)
}

output "vnet_name" {
  value = try(azurerm_virtual_network.main[0].name, null)
}

output "management_subnet_id" {
  value = try(azurerm_subnet.management[0].id, null)
}

output "workload_subnet_id" {
  value = try(azurerm_subnet.workload[0].id, null)
}

output "database_subnet_id" {
  value = try(azurerm_subnet.database[0].id, null)
}