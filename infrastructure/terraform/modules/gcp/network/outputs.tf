output "cloud_sql" {
  description = "Private services access network metadata; dependency ensures peering is ready before Cloud SQL creation."
  value = local.cloud_sql_enabled ? {
    network_id           = google_compute_network.main[0].id
    allocated_range_name = google_compute_global_address.cloud_sql[0].name
  } : null
  depends_on = [google_service_networking_connection.cloud_sql]
}

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
