# The VPC foundation: a VPC, its subnets and outbound routing. Long-lived and
# unaware of which ports the application happens to need.
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
  bastion         = var.config.bastion

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  tags                         = local.common_tags
}

# --------------------------------------------------------------------- bastion
# Core infrastructure, not a workload. Its specification is derived from the
# cloud profile rather than written into vms, so it costs nothing to add a
# provider and cannot drift between them.

module "bastion_spec" {
  source = "../shared/bastion"
  count  = local.is_active ? 1 : 0

  config  = var.config
  cloud   = local.this_cloud
  profile = local.profile
  # AWS reserves the first four addresses of every subnet, so .4 is the first free.
  host_index = 4
}

module "bastion_identity" {
  source = "./modules/identity"
  count  = local.is_active ? 1 : 0

  name        = local.bastion_name
  description = "Runtime identity for the bastion ${local.bastion_name}"
  tags        = local.common_tags
}

module "bastion" {
  source = "./modules/vm"
  count  = local.is_active ? 1 : 0

  name    = local.bastion_name
  vm      = module.bastion_spec[0].vm
  profile = local.profile

  instance_profile_name = module.bastion_identity[0].instance_profile_name
  subnet_id             = module.network[0].public_subnet_id
  security_group_ids    = [module.firewall[0].security_group_ids["bastion"]]

  ssh_users = var.config.ssh_users

  tags = merge(local.common_tags, { role = "bastion" })
}

# -------------------------------------------------------------------- workloads

module "identity" {
  source   = "./modules/identity"
  for_each = local.workload_vms

  name        = "${local.resource_prefix}-${each.key}"
  description = "Runtime identity for the ${each.value.role} workload ${local.resource_prefix}-${each.key}"
  tags        = local.common_tags
}

module "vm" {
  source   = "./modules/vm"
  for_each = local.workload_vms

  name    = "${local.resource_prefix}-${each.key}"
  vm      = each.value
  profile = local.profile

  instance_profile_name = module.identity[each.key].instance_profile_name

  # Reachability on AWS follows the route table, not the address: a workload
  # holding a public IP has to sit in the subnet routed to the gateway.
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

# ---------------------------------------------------------- observability
# Logs and metrics leave every instance through an agent; these grant it the
# right to write, draw the dashboard and decide who hears when a threshold
# breaks. The metric table lives in monitoring, so alerting never names one.

module "logging" {
  source = "./modules/logging"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  identities      = local.identities
  retention_days  = try(var.config.observability.log_retention_days, 30)
  tags            = local.common_tags
}

module "monitoring" {
  source = "./modules/monitoring"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  region          = local.profile.region
  identities      = local.identities
  instances       = local.instances
  thresholds      = try(var.config.observability.thresholds, {})
  tags            = local.common_tags
}

module "alerting" {
  source = "./modules/alerting"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  email           = var.config.observability.alert_email
  metrics         = module.monitoring[0].metrics
  instances       = local.instances
  log_group_name  = module.logging[0].log_group_name
  budget_usd      = try(local.profile.budget_usd, null)
  tags            = local.common_tags
}
