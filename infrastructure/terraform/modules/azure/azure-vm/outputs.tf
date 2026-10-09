output "vms" {
  description = "Azure VM information keyed by logical workload name."
  value = {
    for name, vm in azurerm_linux_virtual_machine.this : name => {
      name                  = vm.name
      id                    = vm.id
      location              = vm.location
      resource_group_name   = var.resource_group_name
      instance_id           = vm.id
      internal_ip           = azurerm_network_interface.vm[name].private_ip_address
      public_ip             = try(azurerm_public_ip.vm[name].ip_address, null)
      network_tags          = local.resolved_vms[name].network_tags
      service_account_email = null
      cloud                 = local.cloud_name
      k3s_role              = try(local.resolved_vms[name].k3s_role, null)
      role                  = local.resolved_vms[name].role
    }
  }
}
