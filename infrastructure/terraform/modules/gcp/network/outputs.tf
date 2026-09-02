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
