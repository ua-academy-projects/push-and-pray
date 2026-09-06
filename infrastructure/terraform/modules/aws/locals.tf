locals {
  this_cloud = "aws"

  profile = try(var.config.clouds[local.this_cloud], null)

  cloud_vms = {
    for name, vm in var.config.vms : name => vm
    if try(vm.cloud, var.config.default_cloud) == local.this_cloud
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

  bastion_vm = one(values(local.bastion_vms))

  # A NAT gateway bills by the hour from the moment it exists. Nothing without
  # a public IP means nothing to route, so it is not created.
  needs_nat_gateway = length([
    for vm in values(local.my_vms) : vm
    if !vm.assign_public_ip
  ]) > 0

  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  common_tags = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
    {
      cloud = local.this_cloud
    },
  )
}
