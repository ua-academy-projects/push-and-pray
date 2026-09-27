output "network_security_group_ids" {
  value = {
    for role, nsg in azurerm_network_security_group.vm : role => nsg.id
  }
}

output "managed_database_nsg_id" {
  value = try(azurerm_network_security_group.managed_database[0].id, null)
}
