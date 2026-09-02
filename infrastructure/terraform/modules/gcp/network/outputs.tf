output "management_subnet_id" {
  description = "ID of the subnet used by the bastion."
  value       = try(google_compute_subnetwork.management["this"].id, null)
}

output "workload_subnet_id" {
  description = "ID of the subnet used by workload VMs."
  value       = try(google_compute_subnetwork.workload["this"].id, null)
}

output "network_tags" {
  description = "Network tags used by firewall rules and Compute Engine instances."
  value       = local.network_tags
}
