output "vms" {
  description = "Created GCP VMs keyed by logical VM name."
  value = {
    for name, vm in google_compute_instance.workload : name => {
      name                  = vm.name
      role                  = local.vms[name].role
      internal_ip           = vm.network_interface[0].network_ip
      public_ip             = try(google_compute_address.public[name].address, null)
      network_tags          = vm.tags
      identity_id           = google_service_account.workload[name].email
      service_account_email = google_service_account.workload[name].email
      secret_ids            = distinct(values(local.vms[name].secret_mappings))
    }
  }
}

output "service_account_emails" {
  description = "GCP service-account emails keyed by logical VM name."
  value = {
    for name, account in google_service_account.workload : name => account.email
  }
}
