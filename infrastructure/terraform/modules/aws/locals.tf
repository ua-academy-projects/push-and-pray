locals {
  this_cloud = "aws"

  profile         = module.selection.profile
  is_active       = module.selection.is_active
  nodes           = module.selection.nodes
  resource_prefix = module.selection.resource_prefix
  common_tags     = module.selection.common_labels

  # Every cloud that hosts a node runs a bastion, so the cloud is part of the
  # name: the Ansible inventory and the tailnet both name a host by it, and
  # three bastions called the same would collapse into one.
  bastion_name = "${local.resource_prefix}-bastion-${local.this_cloud}"

  # A NAT gateway bills by the hour from the moment it exists. The bastion always
  # holds a public address, so only nodes without one create the need for it.
  needs_nat_gateway = length([
    for node in values(local.nodes) : node
    if !node.assign_public_ip
  ]) > 0

  # Every instance on this cloud, the bastion included, in the two shapes the
  # observability modules need: who may write, and what to watch. Count-based,
  # so the bastion joins only when the cloud is active.
  identities = merge(
    { for name in keys(local.nodes) : name => module.identity[name].role_name },
    local.is_active ? { bastion = module.bastion_identity[0].role_name } : {},
  )

  instances = merge(
    {
      for name, node in local.nodes : name => {
        id        = module.vm[name].instance_id
        volume_id = module.vm[name].root_volume_id
        role      = node.role
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
