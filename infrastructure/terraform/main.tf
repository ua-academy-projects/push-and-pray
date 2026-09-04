module "network" {
  source = "./modules/gcp/network"

  name_prefix = local.config.name_prefix
  environment = local.config.environment

  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr

  ui_public_ports = [
    for port in local.config.network.ui_public_ports : tostring(port)
  ]

  bastion_ssh_port             = local.config.vms.bastion.ssh_port
  bastion_allowed_cidrs        = local.config.vms.bastion.allowed_cidrs
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap

  history_api_port = local.config.service_ports.history_api
  postgresql_port  = local.config.service_ports.postgresql

  depends_on = [google_project_service.required]
}

module "vm" {
  source = "./modules/gcp/vm"

  vms           = local.config.vms
  default_cloud = local.config.cloud
  default_image = local.config.image

  machine_types = local.config.machine_types
  disk_types    = local.config.disk_types
  images        = local.config.images

  name_prefix          = local.config.name_prefix
  environment          = local.config.environment
  registry_repository  = local.config.registry.repository
  image_sha            = local.config.registry.image_sha
  ssh_users            = local.config.ssh_users
  common_labels        = local.config.common_labels

  management_subnet_id = module.network.management_subnet_id
  workload_subnet_id   = module.network.workload_subnet_id

  depends_on = [google_project_service.required]
}

module "aws_network" {
  source = "./modules/aws/network"

  name_prefix = local.config.name_prefix
  environment = local.config.environment

  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr

  region  = local.config.region
  regions = local.config.regions

  bastion_ssh_port             = local.config.vms.bastion.ssh_port
  bastion_allowed_cidrs        = local.config.vms.bastion.allowed_cidrs
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap

  history_api_port = local.config.service_ports.history_api
  postgresql_port  = local.config.service_ports.postgresql

  ui_public_ports = [
    for port in local.config.network.ui_public_ports : tostring(port)
  ]
}

module "aws_vm" {
  source = "./modules/aws/vm"

  vms           = local.config.vms
  default_cloud = local.config.cloud
  default_image = local.config.image

  machine_types = local.config.machine_types
  disk_types    = local.config.disk_types
  images        = local.config.images

  name_prefix = local.config.name_prefix
  environment = local.config.environment
  ssh_users   = local.config.ssh_users

  management_subnet_id = module.aws_network.management_subnet_id
  workload_subnet_id   = module.aws_network.workload_subnet_id
  security_group_ids   = module.aws_network.security_group_ids
}
