output "management_subnet_id" {
  description = "ID of the subnet used by the bastion."
  value       = google_compute_subnetwork.management.id
}

output "vm_subnet_id" {
  description = "ID of the subnet used by VMs."
  value       = google_compute_subnetwork.vm.id
}

output "network_id" {
  description = "ID of the application VPC network."
  value       = google_compute_network.main.id
}

output "private_service_connection" {
  description = "Private Services Access connection used by Cloud SQL."
  value       = google_service_networking_connection.private_services.id
}
