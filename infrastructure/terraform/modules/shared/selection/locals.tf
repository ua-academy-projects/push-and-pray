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

  # A bastion exists only to reach workloads. A cloud that hosts none has
  # nothing to reach, so the entire cloud is skipped - the bastion included -
  # rather than standing up a network around a jump host with no destination.
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
    # Last, so the project configuration cannot overwrite it: the Ansible
    # inventory selects hosts by this label.
    {
      cloud = var.cloud
    },
  )
}
