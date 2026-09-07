output "network_id" {
  description = "ID of the VPC network, consumed by the routing and firewall modules."
  value       = google_compute_network.main.id
}

output "management_subnet_id" {
  description = "ID of the subnet used by the bastion."
  value       = google_compute_subnetwork.management.id
}

output "workload_subnet_id" {
  description = "ID of the subnet used by workload VMs."
  value       = google_compute_subnetwork.workload.id
}

output "network_tags" {
  description = "Network tags used by the firewall module and Compute Engine instances."
  value       = local.network_tags
}
