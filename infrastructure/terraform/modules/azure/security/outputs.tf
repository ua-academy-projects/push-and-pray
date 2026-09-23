output "management_nsg_id" {
  value = try(azurerm_network_security_group.management[0].id, null)
}

output "workload_nsg_id" {
  value = try(azurerm_network_security_group.workload[0].id, null)
}