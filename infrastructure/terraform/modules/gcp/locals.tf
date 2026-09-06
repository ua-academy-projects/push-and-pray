locals {
  this_cloud = "gcp"

  profile         = module.selection.profile
  is_active       = module.selection.is_active
  my_vms          = module.selection.my_vms
  workload_vms    = module.selection.workload_vms
  bastion_vms     = module.selection.bastion_vms
  bastion_vm      = module.selection.bastion_vm
  resource_prefix = module.selection.resource_prefix
  common_labels   = module.selection.common_labels
}
