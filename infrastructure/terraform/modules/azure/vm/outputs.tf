output "vms" {
  description = "Azure workload VMs, keyed by name. instance_id is the ARM resource ID; the managed-identity fields replace AWS role_arn / GCP service_account_email."
  value = {
    for name, machine in azurerm_linux_virtual_machine.workload : name => {
      instance_id           = machine.id
      name                  = machine.name
      zone                  = machine.zone
      internal_ip           = machine.private_ip_address
      public_ip             = local.azure_vms[name].assign_public_ip ? azurerm_public_ip.public[name].ip_address : null
      identity_resource_id  = azurerm_user_assigned_identity.workload[name].id
      identity_principal_id = azurerm_user_assigned_identity.workload[name].principal_id
      identity_client_id    = azurerm_user_assigned_identity.workload[name].client_id
    }
  }
}

output "azure_vms" {
  description = "Resolved Azure VM configuration (post cloud/size/image resolution), keyed by name."
  value       = local.azure_vms
}
