output "name" {
  value = try(azurerm_resource_group.main[0].name, null)
}

output "location" {
  value = try(azurerm_resource_group.main[0].location, null)
}

output "id" {
  value = try(azurerm_resource_group.main[0].id, null)
}