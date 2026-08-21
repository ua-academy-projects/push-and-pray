output "name" {
  description = "Name of the workload VM."
  value       = google_compute_instance.workload.name
}

output "internal_ip" {
  description = "Internal IP address of the workload VM."
  value       = google_compute_instance.workload.network_interface[0].network_ip
}

output "public_ip" {
  description = "Static external IP address, or null when none is assigned."
  value       = var.assign_public_ip ? google_compute_address.public[0].address : null
}

output "service_account_email" {
  description = "Runtime service account email attached to the workload VM."
  value       = google_service_account.workload.email
}