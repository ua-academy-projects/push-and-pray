# The VPC foundation: a network, its subnets and outbound routing. Long-lived
# and unaware of which ports the application happens to need.
module "network" {
  source = "./modules/network"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  profile         = local.profile

  depends_on = [google_project_service.required]
}

module "firewall" {
  source = "./modules/firewall"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  network_id      = module.network[0].network_id
  config          = var.config
  bastion         = local.bastion_vm

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
module "vm" {
  source   = "./modules/vm"
  for_each = local.my_vms

  name    = "${local.resource_prefix}-${each.key}"
  vm      = each.value
  profile = local.profile

  subnetwork_id = each.value.role == "bastion" ? module.network[0].management_subnet_id : module.network[0].workload_subnet_id
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

  depends_on = [google_project_service.required]
}
