output "network_security_group_ids" {
  value = { for name, group in azurerm_network_security_group.vm : name => group.id }
}
