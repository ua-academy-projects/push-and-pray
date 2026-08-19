# Root Terraform module.

module "network" {
  source = "./modules/network"

  project_id  = local.config.project_id
  region      = local.config.region
  name_prefix = local.name_prefix
  labels      = local.common_labels

  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr

  postgresql_port     = local.config.network.service_ports.postgresql
  history_api_port    = local.config.network.service_ports.history_api
  fetcher_health_port = local.config.network.service_ports.fetcher_health
  ui_internal_port    = local.config.network.service_ports.ui_internal
  ui_public_ports     = [for port in local.config.network.ui_public_ports : tostring(port)]
  ui_source_ranges    = local.config.network.ui_source_ranges

  ssh_port              = local.config.bastion.ssh_port
  bastion_allowed_cidrs = local.config.bastion.bastion_allowed_cidrs
}

module "bastion" {
  source = "./modules/bastion"

  project_id  = local.config.project_id
  region      = local.config.region
  zone        = local.config.zone
  name_prefix = local.name_prefix
  labels      = local.common_labels

  # The bastion is the only instance in the management subnet.
  subnetwork_id = module.network.management_subnet.id
  network_tag   = module.network.network_tags.bastion

  ssh_port  = local.config.bastion.ssh_port
  ssh_users = var.ssh_users
}

# Workload compute is declared in compute.tf.
