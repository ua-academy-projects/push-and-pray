output "network_name" {
  description = "Name of the application VPC network"
  value       = google_compute_network.main.name
}

output "network_self_link" {
  description = "Self-link of the application VPC network"
  value       = google_compute_network.main.self_link
}

output "subnet_name" {
  description = "Name of the regional application subnet"
  value       = google_compute_subnetwork.main.name
}

output "subnet_self_link" {
  description = "Self-link of the regional application subnet"
  value       = google_compute_subnetwork.main.self_link
}

output "subnet_cidr" {
  description = "Primary IPv4 CIDR range of the application subnet"
  value       = google_compute_subnetwork.main.ip_cidr_range
}

output "router_name" {
  description = "Name of the Cloud Router"
  value       = google_compute_router.main.name
}

output "nat_name" {
  description = "Name of the Cloud NAT gateway"
  value       = google_compute_router_nat.main.name
}

output "reserved_internal_addresses" {
  description = "Reserved internal IPv4 addresses keyed by future VM role"
  value = {
    for role, address in google_compute_address.vm_internal : role => address.address
  }
}

output "vm_network_tags" {
  description = "Network tags that future VMs must use for the managed firewall rules"
  value       = local.vm_network_tags
}

output "service_account_emails" {
  description = "Service-account emails keyed by future VM role"
  value = {
    for role, service_account in google_service_account.vm : role => service_account.email
  }
}

output "secret_ids" {
  description = "Secret Manager secret IDs keyed by deployment secret"
  value = {
    for key, secret in google_secret_manager_secret.deployment : key => secret.secret_id
  }
}

output "secret_resource_names" {
  description = "Fully qualified Secret Manager resource names keyed by deployment secret"
  value = {
    for key, secret in google_secret_manager_secret.deployment : key => secret.name
  }
}

output "ui_external_ipv4_address" {
  description = "Reserved regional external IPv4 address for the future UI VM and DNS record"
  value       = google_compute_address.ui_external.address
}

output "vm_names" {
  description = "Compute Engine instance names keyed by VM role"
  value = {
    for role, instance in google_compute_instance.vm : role => instance.name
  }
}

output "vm_internal_ips" {
  description = "Internal IPv4 addresses attached to the Compute Engine instances"
  value = {
    for role, instance in google_compute_instance.vm : role => instance.network_interface[0].network_ip
  }
}

output "vm_self_links" {
  description = "Compute Engine instance self-links keyed by VM role"
  value = {
    for role, instance in google_compute_instance.vm : role => instance.self_link
  }
}

output "infra_data_disk_name" {
  description = "Name of the persistent data disk attached to the Infra VM"
  value       = google_compute_disk.infra_data.name
}
