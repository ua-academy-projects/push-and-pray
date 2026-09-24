output "vms" {
  description = "Created Azure VMs keyed by logical VM name."
  value = {
    for name, vm in azurerm_linux_virtual_machine.workload : name => {
      id                    = vm.virtual_machine_id
      resource_id           = vm.id
      name                  = vm.name
      role                  = local.vms[name].role
      location              = local.vms[name].location
      internal_ip           = azurerm_network_interface.vm[name].private_ip_address
      public_ip             = try(azurerm_public_ip.vm[name].ip_address, null)
      network_tags          = []
      identity_id           = null
      service_account_email = null
    }
  }
}
