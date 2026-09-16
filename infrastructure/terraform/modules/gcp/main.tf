module "network" {
  source = "./network"
  count  = local.has_vms ? 1 : 0

  resource_prefix = local.resource_prefix
  region          = local.config.regions[local.config.default_region][local.cloud_key].region

  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr

}

module "database" {
  source = "./database"
  count  = local.database_mode == "managed" && local.database_vm_name != null ? 1 : 0

  project_id = local.config.clouds.gcp.project_id
  region     = local.config.regions[local.config.default_region][local.cloud_key].region

  network_id = module.network[0].network_id

  resource_prefix = local.resource_prefix

  labels = local.common_labels

  database                          = local.config.database
  managed_settings                  = local.config.database.managed.gcp
  managed_database_password         = random_password.managed_database[0].result
  managed_database_password_version = parseint(substr(sha256(random_password.managed_database[0].result), 0, 8), 16)
}

resource "random_password" "managed_database" {
  count = local.database_mode == "managed" && local.database_vm_name != null ? 1 : 0

  length  = 32
  special = true

  # This password is interpolated into PostgreSQL connection URLs by the
  # workload templates, so restrict special characters to URI-safe values.
  override_special = "-_"

  lifecycle {
    precondition {
      condition     = length(local.managed_database_secret_ids) > 0
      error_message = "Managed database mode requires at least one POSTGRES_PASSWORD entry in a workload VM's secret_mappings."
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

module "security" {
  source = "./security"
  count  = local.has_vms ? 1 : 0

  network_id      = module.network[0].network_id
  resource_prefix = local.resource_prefix

  ui_public_ports = [
    for port in local.config.network.ui_public_ports : tostring(port)
  ]

  bastion_ssh_port             = local.bastion_vm.ssh_port
  bastion_allowed_cidrs        = local.bastion_vm.allowed_cidrs
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap

  history_api_port = local.config.service_ports.history_api
  postgresql_port  = local.config.service_ports.postgresql
  rabbitmq_port    = local.config.service_ports.rabbitmq
  redis_port       = local.config.service_ports.redis
  managed_mode = (
    local.database_mode == "managed" && local.database_vm_name != null
  )
  managed_database_host = (
    local.database_mode == "managed" && local.database_vm_name != null
    ? module.database[0].host
    : null
  )

}

module "vm" {
  source = "./vm"
  count  = local.has_vms ? 1 : 0

  vms             = local.resolved_vms
  resource_prefix = local.resource_prefix
  common_labels   = local.common_labels
  ssh_users       = local.config.ssh_users

  # Configure the SSH daemon before the bastion is reachable from the
  # Internet, so only bastion.ssh_port needs a public firewall rule.
  bastion_ssh_port = local.bastion_vm.ssh_port

  management_subnet_id = module.network[0].management_subnet_id
  workload_subnet_id   = module.network[0].workload_subnet_id

}

module "secrets" {
  source = "./secrets"

  secret_ids = toset(local.all_secret_ids)
  labels     = local.common_labels

  secret_ids_by_vm = local.secret_ids_by_vm
  workload_service_account_emails = {
    for name, vm in local.workload_vms :
    name => module.vm[0].service_account_emails[name]
  }

  secret_version_managers = var.secret_version_managers
  secret_values = local.database_mode == "managed" && local.database_vm_name != null ? merge(
    { for secret_id in local.managed_database_secret_ids : secret_id => random_password.managed_database[0].result },
    { for secret_id in local.rabbitmq_secret_ids : secret_id => random_password.rabbitmq[0].result },
    { for secret_id in local.redis_secret_ids : secret_id => random_password.redis[0].result },
  ) : {}

}

module "monitoring" {
  source = "./monitoring"
  count  = local.monitoring_enabled ? 1 : 0

  project_id             = local.config.clouds.gcp.project_id
  billing_account_id     = lookup(local.config.clouds.gcp, "billing_account_id", null)
  resource_prefix        = local.resource_prefix
  labels                 = local.common_labels
  settings               = local.monitoring_settings
  uptime_hostname        = try(local.ui_vm.public_endpoint.hostname, null)
  service_account_emails = module.vm[0].service_account_emails

}
