output "bastion_name" {
  description = "Name of the bastion instance."
  value       = google_compute_instance.bastion.name
}

output "bastion_zone" {
  description = "Zone the bastion runs in."
  value       = google_compute_instance.bastion.zone
}

output "bastion_public_ip" {
  description = "Static external IP of the bastion. This is the only address the team connects to."
  value       = google_compute_address.bastion.address
}

output "bastion_private_ip" {
  description = "Internal IP of the bastion inside the VPC."
  value       = google_compute_instance.bastion.network_interface[0].network_ip
}

output "bastion_network_tags" {
  description = "Network tags carried by the bastion. The network module's firewall rules match on these."
  value       = google_compute_instance.bastion.tags
}

output "bastion_service_account" {
  description = "Email of the dedicated bastion service account."
  value       = google_service_account.bastion.email
}

output "ssh_port" {
  description = "Port sshd listens on. The default port 22 is closed."
  value       = var.ssh_port
}

output "ssh_users" {
  description = "Usernames that have a public key installed on the bastion. Keys themselves are not exported."
  value       = sort(keys(var.ssh_users))
}

output "bastion_ssh_command" {
  description = "Ready-to-run SSH command for the bastion. Replace <user> with your own username."
  value       = "ssh -p ${var.ssh_port} <user>@${google_compute_address.bastion.address}"
}

output "bastion_proxy_jump_command" {
  description = "Template for reaching a private instance through the bastion with ProxyJump."
  value       = "ssh -J <user>@${google_compute_address.bastion.address}:${var.ssh_port} -p ${var.ssh_port} <user>@<private-instance-ip>"
}
