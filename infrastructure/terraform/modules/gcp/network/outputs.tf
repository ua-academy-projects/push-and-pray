output "management_subnet_id" {
  description = "ID of the subnet used by the bastion."
  value       = google_compute_subnetwork.management.id
}

output "workload_subnet_id" {
  description = "ID of the subnet used by workload VMs."
  value       = google_compute_subnetwork.workload.id
}

output "network_id" {
  description = "ID of the VPC network used by the security module."
  value       = google_compute_network.main.id
}
