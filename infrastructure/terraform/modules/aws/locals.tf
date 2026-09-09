locals {
  this_cloud = "aws"

  profile         = module.selection.profile
  is_active       = module.selection.is_active
  workload_vms    = module.selection.workload_vms
  resource_prefix = module.selection.resource_prefix
  common_tags     = module.selection.common_labels

  bastion_name = "${local.resource_prefix}-bastion"

  # A NAT gateway bills by the hour from the moment it exists. The bastion always
  # holds a public address, so only workloads can create the need for one.
  needs_nat_gateway = length([
    for vm in values(local.workload_vms) : vm
    if !vm.assign_public_ip
  ]) > 0
}
