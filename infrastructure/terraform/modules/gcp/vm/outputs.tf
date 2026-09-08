output "names" {
  description = "Compute Engine VM names by logical VM key."
  value       = local.vm_names
}

output "private_ips" {
  description = "Internal IPv4 addresses by logical VM key."
  value = {
    for name, instance in google_compute_instance.workload :
    name => instance.network_interface[0].network_ip
  }
}

output "public_ips" {
  description = "External IPv4 addresses by logical VM key, or null when private."
  value = {
    for name, vm in var.vms :
    name => try(google_compute_address.public[name].address, null)
  }
}

output "network_tags" {
  description = "Effective GCP network tags by logical VM key."
  value       = local.network_tags_by_vm
}

output "service_account_emails" {
  description = "Dedicated workload service-account emails by logical VM key."
  value = {
    for name, service_account in google_service_account.workload :
    name => service_account.email
  }
}
