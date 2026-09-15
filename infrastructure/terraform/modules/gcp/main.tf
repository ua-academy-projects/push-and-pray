# The VPC foundation: a network, its subnets and outbound routing. Long-lived
# and unaware of which ports the application happens to need.
module "network" {
  source = "./modules/network"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  profile         = local.profile
}

module "firewall" {
  source = "./modules/firewall"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  network_id      = module.network[0].network_id
  config          = var.config
  bastion         = var.config.bastion

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}

module "bastion_spec" {
  source = "../shared/bastion"
  count  = local.is_active ? 1 : 0

  config     = var.config
  cloud      = local.this_cloud
  profile    = local.profile
  host_index = 2
}

module "bastion_identity" {
  source = "./modules/identity"
  count  = local.is_active ? 1 : 0

  name        = local.bastion_name
  description = "Runtime identity for the bastion ${local.bastion_name}"
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
module "bastion" {
  source = "./modules/vm"
  count  = local.is_active ? 1 : 0

  name    = local.bastion_name
  vm      = module.bastion_spec[0].vm
  profile = local.profile

  service_account_email = module.bastion_identity[0].email
  subnetwork_id         = module.network[0].management_subnet_id
  network_tags          = [module.firewall[0].network_tags["bastion"]]

  ssh_users = var.config.ssh_users

  labels = merge(local.common_labels, { role = "bastion" })
}

module "identity" {
  source   = "./modules/identity"
  for_each = local.workload_vms

  name        = "${local.resource_prefix}-${each.key}"
  description = "Runtime identity for the ${each.value.role} workload ${local.resource_prefix}-${each.key}"
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
module "vm" {
  source   = "./modules/vm"
  for_each = local.workload_vms

  name    = "${local.resource_prefix}-${each.key}"
  vm      = each.value
  profile = local.profile

  service_account_email = module.identity[each.key].email
  subnetwork_id         = module.network[0].workload_subnet_id
  network_tags = [
    for scope in each.value.network_tags :
    module.firewall[0].network_tags[scope]
  ]

  ssh_users = var.config.ssh_users

  labels = merge(
    local.common_labels,
    try(each.value.labels, {}),
    {
      role = each.value.role
    },
  )
}

# ---------------------------------------------------------- observability
# Logs and metrics leave every VM through an agent; these grant it the right
# to write, draw the dashboard and decide who hears when a threshold breaks.
# The metric table lives in monitoring, so alerting never names a metric.

module "logging" {
  source = "./modules/logging"
  count  = local.is_active ? 1 : 0

  project_id     = local.profile.project_id
  identities     = local.identities
  retention_days = try(var.config.observability.log_retention_days, 30)
}

module "monitoring" {
  source = "./modules/monitoring"
  count  = local.is_active ? 1 : 0

  project_id      = local.profile.project_id
  resource_prefix = local.resource_prefix
  identities      = local.identities
  labels          = local.common_labels
  thresholds      = try(var.config.observability.thresholds, {})
}

module "alerting" {
  source = "./modules/alerting"
  count  = local.is_active ? 1 : 0

  project_id      = local.profile.project_id
  resource_prefix = local.resource_prefix
  email           = var.config.observability.alert_email
  metrics         = module.monitoring[0].metrics
  log_name        = module.logging[0].log_name
  budget_usd      = try(local.profile.budget_usd, null)
  billing_account = try(local.profile.billing_account, null)
}
