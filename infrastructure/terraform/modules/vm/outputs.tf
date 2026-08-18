output "name" {
  description = "Instance name."
  value       = google_compute_instance.this.name
}

output "self_link" {
  description = "Instance self link."
  value       = google_compute_instance.this.self_link
}

output "internal_ip" {
  description = "Reserved internal IPv4 address."
  value       = google_compute_address.internal.address
}

output "external_ip" {
  description = "Reserved external IPv4 address, or null when disabled."
  value       = var.assign_external_ip ? google_compute_address.external[0].address : null
}

output "network_tags" {
  description = "Network tags attached to the instance."
  value       = google_compute_instance.this.tags
}
