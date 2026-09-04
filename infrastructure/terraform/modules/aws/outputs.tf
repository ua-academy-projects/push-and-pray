output "vms" {
  description = "Provider-neutral AWS VM records."
  value = {
    for name, vm in module.vm : name => {
      name             = vm.name
      role             = module.config.provisionable_vms[name].role
      cloud            = module.config.cloud
      internal_ip      = vm.internal_ip
      public_ip        = vm.public_ip
      network_tags     = vm.network_tags
      runtime_identity = vm.identity
    }
  }
}

output "configuration_valid" {
  description = "Whether every selected profile, cloud override, and AWS location resolves."
  value       = module.config.configuration_valid
}

output "secret_ids" {
  value = sort(module.config.all_secret_ids)
}

output "secret_resource_names" {
  value = {
    for secret_id in module.config.all_secret_ids :
    secret_id => "/${trimprefix(secret_id, "/")}"
  }
}

output "workload_secret_access" {
  value = {
    for name, workload in module.config.workload_vms :
    name => sort(distinct(values(workload.secret_mappings)))
  }
}
