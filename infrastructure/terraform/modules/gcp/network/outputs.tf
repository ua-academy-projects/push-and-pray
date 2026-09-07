output "management_subnet_id" {
  description = "ID of the subnet used by the bastion, or null when no GCP VMs are configured."
  value       = try(google_compute_subnetwork.management[0].id, null)
}

output "workload_subnet_id" {
  description = "ID of the subnet used by workload VMs, or null when no GCP VMs are configured."
  value       = try(google_compute_subnetwork.workload[0].id, null)
}

output "network_tags" {
  description = "Network tags used by firewall rules and Compute Engine instances."
  value       = local.network_tags
}
