locals {
  this_cloud = "azure"

  profile         = module.selection.profile
  is_active       = module.selection.is_active
  workload_vms    = module.selection.workload_vms
  resource_prefix = module.selection.resource_prefix
  common_tags     = module.selection.common_labels

  bastion_name = "${local.resource_prefix}-bastion"

  # Every resource of the environment sits in this one group. The name is
  # derived, never configured, so the Ansible inventory can derive it too.
  resource_group_name = "${local.resource_prefix}-rg"

  database_managed = module.selection.database_managed
  builds_database  = module.selection.builds_database

  # A NAT gateway bills by the hour from the moment it exists. The bastion always
  # holds a public address, so only workloads can create the need for one.
  needs_nat_gateway = length([
    for vm in values(local.workload_vms) : vm
    if !vm.assign_public_ip
  ]) > 0

  # Every VM on this cloud, the bastion included, in the shape the
  # observability modules need. Count-based, so the bastion joins only when
  # the cloud is active.
  instances = merge(
    {
      for name, vm in local.workload_vms : name => {
        id          = module.vm[name].vm_id
        name        = module.vm[name].name
        role        = vm.role
        identity_id = module.identity[name].id
      }
    },
    local.is_active ? {
      bastion = {
        id          = module.bastion[0].vm_id
        name        = module.bastion[0].name
        role        = "bastion"
        identity_id = module.bastion_identity[0].id
      }
    } : {},
  )
}
