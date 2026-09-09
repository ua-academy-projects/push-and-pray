output "network_id" {
  description = "ID of the VPC network, consumed by the routing and firewall modules."
  value       = try(google_compute_network.main[0].id, null)
}

output "management_subnet_id" {
  description = "ID of the subnet used by the bastion."
  value       = try(google_compute_subnetwork.management[0].id, null)
}

output "workload_subnet_id" {
  description = "ID of the subnet used by workload VMs."
  value       = try(google_compute_subnetwork.workload[0].id, null)
}

output "network_tags" {
  description = "Network tags used by the firewall module and Compute Engine instances."
  value       = local.network_tags
}
