output "names" {
  description = "Names of workload VMs, by VM key."
  value       = { for name, vm in google_compute_instance.workload : name => vm.name }
}

output "internal_ips" {
  description = "Internal IP addresses of workload VMs, by VM key."
  value       = { for name, vm in google_compute_instance.workload : name => vm.network_interface[0].network_ip }
}

output "public_ips" {
  description = "Static public IP addresses, or null when none is assigned, by VM key."
  value = {
    for name, vm in local.selected_vms :
    name => vm.assign_public_ip ? google_compute_address.public[name].address : null
  }
}

output "network_tags" {
  description = "Effective network tags attached to each workload VM, by VM key."
  value       = { for name, vm in google_compute_instance.workload : name => vm.tags }
}

output "service_account_emails" {
  description = "Emails of each workload VM's dedicated service account, by VM key."
  value       = { for name, sa in google_service_account.workload : name => sa.email }
}
