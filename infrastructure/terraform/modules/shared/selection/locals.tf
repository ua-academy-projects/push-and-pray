locals {
  profile = try(var.config.clouds[var.cloud], null)

  cloud_vms = {
    for name, vm in var.config.vms : name => vm
    if try(vm.cloud, var.config.default_cloud) == var.cloud
  }

  workload_vms = {
    for name, vm in local.cloud_vms : name => vm
    if vm.role != "bastion"
  }

  is_active = length(local.workload_vms) > 0

  my_vms = {
    for name, vm in local.cloud_vms : name => vm
    if local.is_active
  }

  bastion_vms = {
    for name, vm in local.my_vms : name => vm
    if vm.role == "bastion"
  }

  common_labels = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
    {
      cloud = var.cloud
    },
  )
}
