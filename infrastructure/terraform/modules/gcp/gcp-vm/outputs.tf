output "vms" {
  value = {
    for name, vm in google_compute_instance.workload : name => {
      name                  = vm.name
      instance_id           = tostring(vm.instance_id)
      internal_ip           = vm.network_interface[0].network_ip
      public_ip             = try(google_compute_address.public[name].address, null)
      network_tags          = vm.tags
      service_account_email = var.service_account_emails[name]
      cloud                 = local.cloud_name
      role                  = local.vms[name].role
    }
  }
}
