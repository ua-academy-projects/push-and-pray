module "network" {
  source = "./modules/network"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  config          = var.config
  profile         = local.profile
  bastion         = local.bastion_vm

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  enable_nat_gateway           = local.needs_nat_gateway
  tags                         = local.common_tags
}

module "vm" {
  source   = "./modules/vm"
  for_each = local.my_vms

  name    = "${local.resource_prefix}-${each.key}"
  vm      = each.value
  profile = local.profile

  # GCP places the bastion by role because an external address works from any
  # subnet there. On AWS reachability follows the route table, so every VM that
  # holds a public IP has to sit in the subnet routed to the gateway.
  subnet_id = each.value.assign_public_ip ? module.network[0].public_subnet_id : module.network[0].private_subnet_id
  security_group_ids = [
    for scope in each.value.network_tags :
    module.network[0].security_group_ids[scope]
  ]

  ssh_users = var.config.ssh_users

  tags = merge(
    local.common_tags,
    try(each.value.labels, {}),
    {
      role = each.value.role
    },
  )
}
