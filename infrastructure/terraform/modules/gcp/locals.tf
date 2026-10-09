locals {
  this_cloud = "gcp"

  profile         = module.selection.profile
  is_active       = module.selection.is_active
  nodes           = module.selection.nodes
  resource_prefix = module.selection.resource_prefix
  common_labels   = module.selection.common_labels

  # Every cloud that hosts a node runs a bastion, so the cloud is part of the
  # name: the Ansible inventory and the tailnet both name a host by it, and
  # three bastions called the same would collapse into one.
  bastion_name = "${local.resource_prefix}-bastion-${local.this_cloud}"

  identities = merge(
    { for name in keys(local.nodes) : name => module.identity[name].member },
    local.is_active ? { bastion = module.bastion_identity[0].member } : {},
  )
}
