output "public_ips" {
  description = "Static public IP addresses allocated for VMs with assign_public_ip = true, by VM key."
  value       = { for name, addr in google_compute_address.public : name => addr.address }
}
