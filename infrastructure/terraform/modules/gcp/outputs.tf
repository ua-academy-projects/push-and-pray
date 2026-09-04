output "vms" {
  value = {
    for name, vm in local.vms : name => {
      name                  = module.vm[name].name
      cloud                 = local.cloud
      role                  = vm.role
      internal_ip           = module.vm[name].internal_ip
      public_ip             = module.vm[name].public_ip
      network_tags          = module.vm[name].network_tags
      service_account_email = module.vm[name].service_account_email
      secret_access         = sort(distinct(values(vm.secret_mappings)))
    }
  }
}