output "resource_group_name" {
  description = "Resource group that owns every Azure resource in this deployment, or null when no Azure feature is selected."
  value       = try(azurerm_resource_group.main[0].name, null)
}

output "resource_group_id" {
  description = "ARM ID of the resource group; the scope the Azure budget is written against."
  value       = try(azurerm_resource_group.main[0].id, null)
}

output "location" {
  description = "Azure location every resource in this deployment is created in."
  value       = local.location
}

output "vnet_id" {
  value = try(azurerm_virtual_network.main[0].id, null)
}

output "vm_subnet_ids" {
  description = "Subnet ID per VM key, selected by which configured subnet contains the VM's internal_ip."
  value       = { for name, subnet in local.vm_subnets : name => azurerm_subnet.main[subnet].id }
}

output "security_group_ids" {
  description = "NIC-associated network security group IDs by role."
  value       = { for role, nsg in azurerm_network_security_group.role : role => nsg.id }
}

output "application_security_group_ids" {
  description = "Application security group IDs by role; the security rules reference these instead of addresses."
  value       = { for role, asg in azurerm_application_security_group.role : role => asg.id }
}

output "postgres" {
  description = "Delegated subnet and private DNS zone for Flexible Server; null outside Azure cloud database mode. The dependency carries link readiness, which a bare ID would not."
  value = local.postgres_enabled ? {
    subnet_id           = azurerm_subnet.postgres[0].id
    private_dns_zone_id = azurerm_private_dns_zone.postgres[0].id
  } : null
  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}
