output "names" {
  value = { for name, vm in azurerm_linux_virtual_machine.workload : name => "${local.resource_prefix}-${name}" }
}

output "internal_ips" {
  value = { for name, vm in azurerm_linux_virtual_machine.workload : name => vm.private_ip_address }
}

output "public_ips" {
  value = {
    for name, vm in local.selected_vms :
    name => vm.assign_public_ip ? azurerm_public_ip.workload[name].ip_address : null
  }
}

output "ids" {
  value = { for name, vm in azurerm_linux_virtual_machine.workload : name => vm.id }
}