output "vnet_id" {
  description = "ID of the virtual network."
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the virtual network."
  value       = azurerm_virtual_network.main.name
}

output "management_subnet_id" {
  description = "ID of the subnet the bastion lives in."
  value       = azurerm_subnet.management.id
}

output "workload_subnet_id" {
  description = "ID of the subnet every workload lives in, public address or not."
  value       = azurerm_subnet.workload.id
}

output "subnet_ids" {
  description = "Every subnet by purpose, for the firewall module to attach the security group to. The keys are known before apply, so they can drive for_each."
  value = {
    management = azurerm_subnet.management.id
    workload   = azurerm_subnet.workload.id
  }
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway, or null when no VM needs one."
  value       = one(azurerm_nat_gateway.main[*].id)
}

output "nat_public_ip" {
  description = "Address every workload without a public IP appears to come from, or null when no NAT gateway exists. Useful for allowlisting this deployment upstream."
  value       = one(azurerm_public_ip.nat[*].ip_address)
}
