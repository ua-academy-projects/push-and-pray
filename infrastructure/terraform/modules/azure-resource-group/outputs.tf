output "name" {
  description = "Azure resource group name."
  value       = try(azurerm_resource_group.this["main"].name, null)
}

output "id" {
  description = "Azure resource group ID."
  value       = try(azurerm_resource_group.this["main"].id, null)
}

output "location" {
  description = "Azure resource group region."
  value       = try(azurerm_resource_group.this["main"].location, null)
}
