locals {
  this_cloud = "aws"

  profile         = module.selection.profile
  is_active       = module.selection.is_active
  workload_vms    = module.selection.workload_vms
  resource_prefix = module.selection.resource_prefix
  common_tags     = module.selection.common_labels

  bastion_name = "${local.resource_prefix}-bastion"

  database_managed = module.selection.database_managed
  builds_database  = module.selection.builds_database

  # A NAT gateway bills by the hour from the moment it exists. The bastion always
  # holds a public address, so only workloads can create the need for one.
  needs_nat_gateway = length([
    for vm in values(local.workload_vms) : vm
    if !vm.assign_public_ip
  ]) > 0

  # Every instance on this cloud, the bastion included, in the two shapes the
  # observability modules need: who may write, and what to watch. Count-based,
  # so the bastion joins only when the cloud is active.
  identities = merge(
    { for name in keys(local.workload_vms) : name => module.identity[name].role_name },
    local.is_active ? { bastion = module.bastion_identity[0].role_name } : {},
  )

  instances = merge(
    {
      for name, vm in local.workload_vms : name => {
        id        = module.vm[name].instance_id
        volume_id = module.vm[name].root_volume_id
        role      = vm.role
        name      = module.vm[name].name
      }
    },
    local.is_active ? {
      bastion = {
        id        = module.bastion[0].instance_id
        volume_id = module.bastion[0].root_volume_id
        role      = "bastion"
        name      = module.bastion[0].name
      }
    } : {},
  )
}
