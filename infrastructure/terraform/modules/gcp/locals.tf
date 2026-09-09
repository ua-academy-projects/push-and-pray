locals {
  this_cloud = "gcp"

  profile         = module.selection.profile
  is_active       = module.selection.is_active
  workload_vms    = module.selection.workload_vms
  resource_prefix = module.selection.resource_prefix
  common_labels   = module.selection.common_labels

  bastion_name = "${local.resource_prefix}-bastion"
}
