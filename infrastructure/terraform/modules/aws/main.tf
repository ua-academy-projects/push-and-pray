module "network" {
  source = "./network"
  count  = local.has_vms ? 1 : 0

  resource_prefix = local.resource_prefix

  vpc_cidr = local.network_config.vpc_cidr

  management_subnet_cidr = local.network_config.management_subnet_cidr

  workload_subnet_cidr = local.network_config.workload_subnet_cidr

  database_subnets = lookup(local.network_config, "database_subnets", [])

  availability_zone = local.config.regions[local.config.default_region][local.cloud_key].availability_zone

}

module "secrets" {
  source     = "./secrets"
  secret_ids = local.all_secret_ids
  tags       = local.common_labels
  secret_values = local.database_mode == "managed" && local.database_vm_name != null ? merge(
    { for secret_id in local.managed_database_secret_ids : secret_id => random_password.managed_database[0].result },
    { for secret_id in local.rabbitmq_secret_ids : secret_id => random_password.rabbitmq[0].result },
    { for secret_id in local.redis_secret_ids : secret_id => random_password.redis[0].result },
  ) : {}
}

resource "random_password" "managed_database" {
  count = local.database_mode == "managed" && local.database_vm_name != null ? 1 : 0

  length  = 32
  special = true

  # The workload templates interpolate this value in PostgreSQL URLs.
  override_special = "-_"

  lifecycle {
    precondition {
      condition     = length(local.managed_database_secret_ids) > 0
      error_message = "Managed database mode requires at least one POSTGRES_PASSWORD entry in an AWS workload VM's secret_mappings."
    }
  }
}

resource "random_password" "rabbitmq" {
  count = local.database_mode == "managed" && local.database_vm_name != null ? 1 : 0

  length           = 32
  special          = true
  override_special = "-_"

  lifecycle {
    precondition {
      condition     = length(local.rabbitmq_secret_ids) > 0
      error_message = "Managed mode requires RABBITMQ_PASSWORD secret mappings."
    }
  }
}

resource "random_password" "redis" {
  count = local.database_mode == "managed" && local.database_vm_name != null ? 1 : 0

  length           = 32
  special          = true
  override_special = "-_"

  lifecycle {
    precondition {
      condition     = length(local.redis_secret_ids) > 0
      error_message = "Managed mode requires REDIS_PASSWORD secret mappings."
    }
  }
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
  rabbitmq_port    = local.config.service_ports.rabbitmq
  redis_port       = local.config.service_ports.redis
  k3s_node_cidr    = local.network_config.vpc_cidr
  tailscale_transit_remote_cidrs = [
    for cloud, network in local.config.network : network.vpc_cidr
    if contains(["gcp", "aws", "azure"], cloud) && cloud != local.cloud_key
  ]
  k3s_remote_node_cidrs = [
    for cloud, network in local.config.network : network.vpc_cidr
    if contains(["gcp", "aws", "azure"], cloud) && cloud != local.cloud_key
  ]

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  managed_database_enabled     = local.database_mode == "managed" && local.database_vm_name != null
}

module "database" {
  source = "./database"
  count  = local.database_mode == "managed" && local.database_vm_name != null ? 1 : 0

  resource_prefix     = local.resource_prefix
  database            = local.config.database
  managed_settings    = local.config.database.managed.aws
  database_subnet_ids = module.network[0].database_subnet_ids
  security_group_id   = module.security[0].managed_database_security_group_id
  password            = random_password.managed_database[0].result
  tags                = local.common_labels
}

module "vm" {
  source = "./vm"

  count = local.has_vms ? 1 : 0

  vms             = local.resolved_vms
  resource_prefix = local.resource_prefix

  common_labels = local.common_labels

  # Configure the SSH daemon before the bastion is reachable from the
  # Internet, so only bastion.ssh_port needs a public security-group rule.
  bastion_ssh_port = local.bastion_vm.ssh_port
  ssh_users        = local.config.ssh_users

  key_name = module.operator_key[0].key_name

  management_subnet_id = module.network[0].management_subnet_id

  workload_subnet_id = module.network[0].workload_subnet_id

  security_group_ids = module.security[0].security_group_ids

  secret_arns_by_vm = local.secret_arns_by_vm
  secret_ids_by_vm  = local.secret_ids_by_vm
}

resource "aws_route" "tailscale_remote_cloud" {
  for_each = local.has_vms ? {
    for cloud, network in local.config.network : cloud => network.vpc_cidr
    if contains(["gcp", "aws", "azure"], cloud) && cloud != local.cloud_key
  } : {}

  route_table_id         = module.network[0].workload_route_table_id
  destination_cidr_block = each.value
  network_interface_id   = module.vm[0].network_interface_ids[one([for name, vm in local.resolved_vms : name if vm.role == "bastion"])]
}

module "monitoring" {
  source = "./monitoring"
  count  = local.monitoring_enabled ? 1 : 0

  resource_prefix              = local.resource_prefix
  tags                         = local.common_labels
  settings                     = local.monitoring_settings
  instance_ids                 = module.vm[0].instance_ids
  managed_database_enabled     = local.database_mode == "managed"
  database_instance_identifier = local.database_mode == "managed" ? module.database[0].instance_identifier : null
  uptime_hostname              = try(local.ui_vm.public_endpoint.hostname, null)
}
