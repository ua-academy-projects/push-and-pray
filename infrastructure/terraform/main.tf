module "network" {
  count  = length(local.gcp_placements) > 0 ? 1 : 0
  source = "./modules/network"

  resource_prefix = local.resource_prefix
  region          = local.gcp_region
  config          = local.config.network
  depends_on      = [google_project_service.required]
}

module "gcp_firewall" {
  count  = length(local.gcp_placements) > 0 ? 1 : 0
  source = "./modules/gcp_firewall"

  resource_prefix = local.resource_prefix
  network_id      = module.network[0].network_id
  policy          = local.firewall_policy
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
module "vm" {
  source = "./modules/vm"

  config          = local.config
  resource_prefix = local.resource_prefix
  common_labels   = local.common_labels
  ssh_users       = local.config.ssh_users
  startup_scripts = local.startup_scripts
  network = length(local.gcp_placements) > 0 ? {
    management_subnet_id = module.network[0].management_subnet_id
    workload_subnet_id   = module.network[0].workload_subnet_id
  } : null

  depends_on = [google_project_service.required]
}

module "aws_network" {
  count  = length(local.aws_placements) > 0 ? 1 : 0
  source = "./modules/aws_network"

  resource_prefix   = local.resource_prefix
  availability_zone = local.aws_zone
  config            = local.config.network
  tags              = local.common_labels
}

module "aws_security_groups" {
  count  = length(local.aws_placements) > 0 ? 1 : 0
  source = "./modules/aws_security_groups"

  resource_prefix = local.resource_prefix
  vpc_id          = module.aws_network[0].vpc_id
  policy          = local.firewall_policy
  tags            = local.common_labels
}

module "aws_vm" {
  source = "./modules/aws_vm"

  config          = local.config
  resource_prefix = local.resource_prefix
  common_labels   = local.common_labels
  ssh_users       = local.config.ssh_users
  startup_scripts = local.startup_scripts
  network = length(local.aws_placements) > 0 ? {
    management_subnet_id = module.aws_network[0].management_subnet_id
    workload_subnet_id   = module.aws_network[0].workload_subnet_id
    security_group_ids   = module.aws_security_groups[0].security_group_ids
  } : null

  depends_on = [module.aws_network]
}
