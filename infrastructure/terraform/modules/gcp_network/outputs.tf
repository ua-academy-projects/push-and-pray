output "management_subnet_id" {
  description = "ID of the subnet used by the bastion."
  value       = google_compute_subnetwork.management.id
}

output "vm_subnet_id" {
  description = "ID of the subnet used by VMs."
  value       = google_compute_subnetwork.vm.id
}