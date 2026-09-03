module "network" {
  source = "./network"
  count  = local.has_vms ? 1 : 0

  resource_prefix = local.resource_prefix

  vpc_cidr = local.config.network.vpc_cidr

  management_subnet_cidr = local.config.network.management_subnet_cidr

  workload_subnet_cidr = local.config.network.workload_subnet_cidr

  availability_zone = local.config.regions[local.config.default_region][var.cloud_key].availability_zone

  ui_public_ports = [
    for port in local.config.network.ui_public_ports :
    tostring(port)
  ]


  bastion_ssh_port = local.bastion_vm.ssh_port

  bastion_allowed_cidrs = local.bastion_vm.allowed_cidrs

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap

  history_api_port = local.config.service_ports.history_api

  postgresql_port = local.config.service_ports.postgresql

}

module "vm" {
  source = "./vm"

  count = local.has_vms ? 1 : 0

  vms             = local.resolved_vms
  resource_prefix = local.resource_prefix

  common_labels = local.common_labels

  key_name = aws_key_pair.operator[0].key_name

  management_subnet_id = module.network[0].management_subnet_id

  workload_subnet_id = module.network[0].workload_subnet_id

  security_group_ids = module.network[0].security_group_ids
}
