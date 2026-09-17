locals {
  this_cloud = "gcp"

  profile         = module.selection.profile
  is_active       = module.selection.is_active
  workload_vms    = module.selection.workload_vms
  resource_prefix = module.selection.resource_prefix
  common_labels   = module.selection.common_labels

  bastion_name = "${local.resource_prefix}-bastion"

  database_managed = module.selection.database_managed
  builds_database  = module.selection.builds_database

  identities = merge(
    { for name in keys(local.workload_vms) : name => module.identity[name].member },
    local.is_active ? { bastion = module.bastion_identity[0].member } : {},
  )
}
