output "vms" {
  description = "Provider-neutral GCP VM records."
  value = {
    for name, vm in module.vm : name => {
      name             = vm.name
      role             = local.effective_vms[name].role
      cloud            = local.module_cloud
      internal_ip      = vm.internal_ip
      public_ip        = vm.public_ip
      network_tags     = vm.network_tags
      runtime_identity = vm.service_account_email
    }
  }

}

output "profiles_valid" {
  description = "Whether every selected VM resolves all abstract profiles."
  value = alltrue([
    for vm in values(local.effective_vms) :
    vm.machine_type != null && vm.image != null && vm.disk_type != null
  ])
}

output "secret_ids" {
  value = sort(local.all_secret_ids)
}

output "secret_resource_names" {
  value = {
    for secret_id, secret in google_secret_manager_secret.this :
    secret_id => secret.name
  }
}

output "workload_secret_access" {
  value = {
    for name, workload in local.workload_vms :
    name => sort(distinct(values(workload.secret_mappings)))
  }
}
