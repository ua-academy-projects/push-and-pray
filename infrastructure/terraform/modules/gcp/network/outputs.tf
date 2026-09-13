output "management_subnet_ids" {
  description = "GCP management subnet IDs keyed by abstract location."
  value       = { for location, subnet in google_compute_subnetwork.management : location => subnet.id }
}

output "workload_subnet_ids" {
  description = "GCP workload subnet IDs keyed by abstract location."
  value       = { for location, subnet in google_compute_subnetwork.workload : location => subnet.id }
}

output "network_tags" {
  description = "GCP network tags keyed by abstract location and VM role."
  value       = local.network_tags
}

output "default_network_id" {
  description = "VPC ID in the default location, used by the single managed database."
  value       = try(google_compute_network.main[var.config.default_location].id, null)
}

output "database_private_service_connection" {
  description = "Private Services Access connection for Cloud SQL."
  value       = try(google_service_networking_connection.database[0].id, null)
}

output "database_private_service_enabled" {
  description = "Whether Private Services Access is enabled for Cloud SQL."
  value       = local.managed_database_enabled
}
