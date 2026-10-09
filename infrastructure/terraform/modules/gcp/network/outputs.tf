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

output "network_self_link" {
  value = try(google_compute_network.main[0].self_link, null)
}

output "workload_subnet_self_link" {
  value = try(google_compute_subnetwork.workload[0].self_link, null)
}

output "gke_pods_range_name" {
  value = var.managed_kubernetes_enabled ? local.gke_pods_range_name : null
}

output "gke_services_range_name" {
  value = var.managed_kubernetes_enabled ? local.gke_services_range_name : null
}
