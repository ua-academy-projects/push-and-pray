module "network" {
  source = "./network"

  config                     = var.config
  has_selected_vms           = local.has_selected_vms
  managed_kubernetes_enabled = local.managed_kubernetes_enabled
}

module "routing" {
  source = "./routing"

  config               = var.config
  has_selected_vms     = local.has_selected_vms
  vpc_id               = module.network.vpc_id
  management_subnet_id = module.network.management_subnet_id
  workload_subnet_id   = module.network.workload_subnet_id

  managed_kubernetes_enabled = local.managed_kubernetes_enabled
  kubernetes_subnet_id       = module.network.kubernetes_subnet_id
}

module "security_groups" {
  source = "./security_groups"

  config           = var.config
  selected_vms     = local.selected_vms
  has_selected_vms = local.has_selected_vms
  vpc_id           = module.network.vpc_id
}

module "iam" {
  source = "./iam"

  config       = var.config
  selected_vms = local.selected_vms
}

module "addresses" {
  source = "./addresses"

  config       = var.config
  selected_vms = local.selected_vms
}

module "vm" {
  source = "./vm"

  config       = var.config
  selected_vms = local.selected_vms

  management_subnet_id   = module.network.management_subnet_id
  workload_subnet_id     = module.network.workload_subnet_id
  security_group_ids     = module.security_groups.security_group_ids
  instance_profile_names = module.iam.instance_profile_names
  allocation_ids         = module.addresses.allocation_ids
  public_ips             = module.addresses.public_ips
}

module "secrets" {
  source = "./secrets"

  config                      = var.config
  selected_vms                = local.selected_vms
  iam_role_names              = module.iam.iam_role_names
  aws_secret_version_managers = var.aws_secret_version_managers
}

module "monitoring" {
  source = "./monitoring"

  config           = var.config
  selected_vms     = local.selected_vms
  has_selected_vms = local.has_selected_vms
  instance_ids     = module.vm.ids
}

module "rds" {
  source = "./rds"

  config                = var.config
  has_selected_vms      = local.has_selected_vms
  vpc_id                = module.network.vpc_id
  database_subnet_ids   = module.network.database_subnet_ids
  db_password_secret_id = try(module.secrets.secret_arns[local.db_password_secret_id], null)

  depends_on = [module.network, module.secrets]
}

module "eks" {
  source = "./eks"

  config                    = var.config
  enabled                   = local.managed_kubernetes_enabled
  subnet_ids                = compact([module.network.workload_subnet_id, module.network.kubernetes_subnet_id])
  bastion_security_group_id = module.security_groups.security_group_ids.bastion

  depends_on = [module.routing]
}

resource "random_password" "postgres" {
  count   = local.has_selected_vms && !local.managed_db_enabled && local.db_password_secret_id != null ? 1 : 0
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret_version" "postgres" {
  count = local.has_selected_vms && !local.managed_db_enabled && local.db_password_secret_id != null ? 1 : 0

  secret_id     = module.secrets.secret_arns[local.db_password_secret_id]
  secret_string = random_password.postgres[0].result
}

resource "random_password" "rabbitmq" {
  count   = local.has_selected_vms ? 1 : 0
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret_version" "rabbitmq" {
  count = local.has_selected_vms && local.rabbitmq_password_secret_id != null ? 1 : 0

  secret_id     = module.secrets.secret_arns[local.rabbitmq_password_secret_id]
  secret_string = random_password.rabbitmq[0].result
}

resource "random_password" "redis" {
  count   = local.has_selected_vms ? 1 : 0
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret_version" "redis" {
  count = local.has_selected_vms && local.redis_password_secret_id != null ? 1 : 0

  secret_id     = module.secrets.secret_arns[local.redis_password_secret_id]
  secret_string = random_password.redis[0].result
}
resource "random_password" "grafana" {
  count   = local.has_selected_vms && local.grafana_password_secret_id != null ? 1 : 0
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret_version" "grafana" {
  count = local.has_selected_vms && local.grafana_password_secret_id != null ? 1 : 0

  secret_id     = module.secrets.secret_arns[local.grafana_password_secret_id]
  secret_string = random_password.grafana[0].result
}
