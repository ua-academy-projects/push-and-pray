output "public_ips" {
  description = "Static public IP addresses keyed by logical VM name."
  value = {
    for name, address in azurerm_public_ip.this : name => address.ip_address
  }
}

output "instance_ids" {
  description = "Azure virtual machine IDs keyed by logical VM name."
  value = {
    for name, vm in azurerm_linux_virtual_machine.this : name => vm.id
  }
}
