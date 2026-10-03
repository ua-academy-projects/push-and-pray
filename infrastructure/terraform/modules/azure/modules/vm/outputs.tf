output "name" {
  description = "Name of the VM."
  value       = azurerm_linux_virtual_machine.workload.name
}

output "vm_id" {
  description = "Resource ID of the VM, which metrics and alerts are scoped to."
  value       = azurerm_linux_virtual_machine.workload.id
}

output "internal_ip" {
  description = "Private IP address of the VM."
  value       = azurerm_network_interface.main.private_ip_address
}

output "public_ip" {
  description = "Static public address, or null when none is assigned."
  value       = one(azurerm_public_ip.public[*].ip_address)
}

output "application_security_group_ids" {
  description = "Application security groups the VM's network interface belongs to."
  value       = sort(values(var.application_security_group_ids))
}

output "network_interface_id" {
  description = "ID of the VM's network interface."
  value       = azurerm_network_interface.main.id
}

output "zone" {
  description = "Zone the VM runs in."
  value       = azurerm_linux_virtual_machine.workload.zone
}

output "vm_size" {
  description = "VM size the size label resolved to."
  value       = local.vm_size
}

output "boot_disk" {
  description = "What the boot disk labels resolved to, alongside the size actually used."
  value = {
    image   = var.profile.images[var.vm.image]
    type    = local.boot_disk_type
    size_gb = local.boot_disk_size_gb
  }
}

output "role" {
  description = "Functional role of this VM, echoed back for callers indexing by role."
  value       = var.vm.role
}
