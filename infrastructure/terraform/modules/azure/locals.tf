locals {
  this_cloud = "azure"

  profile         = module.selection.profile
  is_active       = module.selection.is_active
  nodes           = module.selection.nodes
  resource_prefix = module.selection.resource_prefix
  common_tags     = module.selection.common_labels

  # Every cloud that hosts a node runs a bastion, so the cloud is part of the
  # name: the Ansible inventory and the tailnet both name a host by it, and
  # three bastions called the same would collapse into one.
  bastion_name = "${local.resource_prefix}-bastion-${local.this_cloud}"

  # Every resource of the environment sits in this one group. The name is
  # derived, never configured, so the Ansible inventory can derive it too.
  resource_group_name = "${local.resource_prefix}-rg"

  # A NAT gateway bills by the hour from the moment it exists. The bastion always
  # holds a public address, so only nodes without one create the need for it.
  needs_nat_gateway = length([
    for node in values(local.nodes) : node
    if !node.assign_public_ip
  ]) > 0

  # Every VM on this cloud, the bastion included, in the shape the
  # observability modules need. Count-based, so the bastion joins only when
  # the cloud is active.
  instances = merge(
    {
      for name, node in local.nodes : name => {
        id          = module.vm[name].vm_id
        name        = module.vm[name].name
        role        = node.role
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
