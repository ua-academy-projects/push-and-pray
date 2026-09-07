module "network" {
  source = "./network"
  count  = local.has_vms ? 1 : 0

  resource_prefix = local.resource_prefix

  vpc_cidr = local.config.network.vpc_cidr

  management_subnet_cidr = local.config.network.management_subnet_cidr

  workload_subnet_cidr = local.config.network.workload_subnet_cidr

  availability_zone = local.config.regions[local.config.default_region][local.cloud_key].availability_zone

}

module "secrets" {
  source     = "./secrets"
  secret_ids = local.all_secret_ids
  tags       = local.common_labels
}

module "operator_key" {
  source = "./operator_key"

  count = local.has_vms ? 1 : 0

  key_name = "${local.resource_prefix}-operator"

  public_key = local.config.ssh_users["example-operator"]

  tags = local.common_labels

}

module "security" {
  source = "./security"

  count = local.has_vms ? 1 : 0

  vpc_id = module.network[0].vpc_id

  resource_prefix = local.resource_prefix

  tags = local.common_labels

  bastion_ssh_port      = local.bastion_vm.ssh_port
  bastion_allowed_cidrs = local.bastion_vm.allowed_cidrs

  ui_public_ports = [
    for port in local.config.network.ui_public_ports :
    tostring(port)
  ]

  history_api_port = local.config.service_ports.history_api
  postgresql_port  = local.config.service_ports.postgresql

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}

module "vm" {
  source = "./vm"

  count = local.has_vms ? 1 : 0

  vms             = local.resolved_vms
  resource_prefix = local.resource_prefix

  common_labels = local.common_labels

  key_name = module.operator_key[0].key_name

  management_subnet_id = module.network[0].management_subnet_id

  workload_subnet_id = module.network[0].workload_subnet_id

  security_group_ids = module.security[0].security_group_ids

  secret_arns_by_vm = local.secret_arns_by_vm
}
