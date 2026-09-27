output "names" {
  value = local.vm_names
}

output "private_ips" {
  value = {
    for name, nic in azurerm_network_interface.vm :
    name => nic.private_ip_address
  }
}

output "public_ips" {
  value = {
    for name, vm in var.vms :
    name => try(azurerm_public_ip.vm[name].ip_address, null)
  }
}

output "virtual_machine_ids" {
  value = {
    for name, vm in azurerm_linux_virtual_machine.vm : name => vm.id
  }
}

output "principal_ids" {
  value = {
    for name, vm in azurerm_linux_virtual_machine.vm : name => vm.identity[0].principal_id
  }
}
