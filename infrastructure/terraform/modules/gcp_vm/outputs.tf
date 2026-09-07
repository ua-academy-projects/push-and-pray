output "vms" {
  description = "Created GCP VMs keyed by configuration name."

  value = {
    for name, vm in google_compute_instance.vms : name => {
      name                  = vm.name
      cloud                 = "gcp"
      role                  = local.vms[name].role
      internal_ip           = vm.network_interface[0].network_ip
      public_ip             = local.vms[name].assign_public_ip ? google_compute_address.public[name].address : null
      network_tags          = vm.tags
      service_account_email = local.vms[name].role == "bastion" ? null : var.service_account_emails[name]
      secret_access         = sort(distinct(values(local.vms[name].secret_mappings)))
    }
  }
}
