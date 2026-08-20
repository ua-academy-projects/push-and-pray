output "instance_name" {
  description = "Name of the bastion VM."
  value       = google_compute_instance.bastion.name
}

output "public_ip" {
  description = "Static external IP address of the bastion VM."
  value       = google_compute_address.bastion.address
}