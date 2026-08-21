output "instance_name" {
  description = "Name of the bastion VM."
  value       = google_compute_instance.bastion.name
}

output "public_ip" {
  description = "Static external IP address of the bastion VM."
  value       = google_compute_address.bastion.address
}

output "network_tags" {
  description = "Effective network tags attached to the bastion VM."
  value       = google_compute_instance.bastion.tags
}

output "service_account_email" {
  description = "Email of the bastion VM's dedicated service account."
  value       = google_service_account.bastion.email
}
