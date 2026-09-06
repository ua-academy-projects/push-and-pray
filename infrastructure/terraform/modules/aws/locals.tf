locals {
  this_cloud = "aws"

  profile         = module.selection.profile
  is_active       = module.selection.is_active
  my_vms          = module.selection.my_vms
  workload_vms    = module.selection.workload_vms
  bastion_vms     = module.selection.bastion_vms
  bastion_vm      = module.selection.bastion_vm
  resource_prefix = module.selection.resource_prefix
  common_tags     = module.selection.common_labels

  # A NAT gateway bills by the hour from the moment it exists. Nothing without
  # a public IP means nothing to route, so it is not created.
  needs_nat_gateway = length([
    for vm in values(local.my_vms) : vm
    if !vm.assign_public_ip
  ]) > 0
}
