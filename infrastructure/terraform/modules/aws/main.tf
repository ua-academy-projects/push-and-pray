module "network" {
  source = "./modules/network"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  profile         = local.profile

  enable_nat_gateway = local.needs_nat_gateway
  tags               = local.common_tags
}

module "firewall" {
  source = "./modules/firewall"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  vpc_id          = module.network[0].vpc_id
  config          = var.config
  bastion         = local.bastion_vm

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  tags                         = local.common_tags
}

module "identity" {
  source   = "./modules/identity"
  for_each = local.my_vms

  name        = "${local.resource_prefix}-${each.key}"
  description = "Runtime identity for the ${each.value.role} workload ${local.resource_prefix}-${each.key}"
  tags        = local.common_tags
}

module "vm" {
  source   = "./modules/vm"
  for_each = local.my_vms

  name    = "${local.resource_prefix}-${each.key}"
  vm      = each.value
  profile = local.profile

  instance_profile_name = module.identity[each.key].instance_profile_name
  subnet_id = each.value.assign_public_ip ? module.network[0].public_subnet_id : module.network[0].private_subnet_id
  security_group_ids = [
    for scope in each.value.network_tags :
    module.firewall[0].security_group_ids[scope]
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
