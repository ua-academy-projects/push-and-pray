module "network" {
  source = "./network"
  count  = local.has_vms ? 1 : 0

  resource_prefix = local.resource_prefix
  region          = local.config.regions[local.config.default_region][local.cloud_key].region

  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr

  depends_on = [google_project_service.required]
}

module "database" {
  source = "./database"
  count  = local.database_mode == "managed" ? 1 : 0

  project_id = local.config.clouds.gcp.project_id
  region     = local.config.regions[local.config.default_region][local.cloud_key].region

  network_id = module.network[0].network_id

  resource_prefix = local.resource_prefix

  labels = local.common_labels

  database                          = local.config.database
  managed_settings                  = local.config.database.managed.gcp
  managed_database_password         = var.managed_database_password
  managed_database_password_version = var.managed_database_password_version
  depends_on                        = [google_project_service.required]
}

module "messaging" {
  source = "./messaging"
  count  = local.has_vms ? 1 : 0

  project_id      = local.config.clouds.gcp.project_id
  resource_prefix = local.resource_prefix
  labels          = local.common_labels
  settings        = local.config.messaging

  publisher_service_account_email = module.vm[0].service_account_emails[local.fetcher_vm_name]
  consumer_service_account_email  = module.vm[0].service_account_emails[local.history_vm_name]

  depends_on = [google_project_service.required]
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

  depends_on = [google_project_service.required]
}

module "vm" {
  source = "./vm"
  count  = local.has_vms ? 1 : 0

  vms             = local.resolved_vms
  resource_prefix = local.resource_prefix
  common_labels   = local.common_labels
  ssh_users       = local.config.ssh_users

  management_subnet_id = module.network[0].management_subnet_id
  workload_subnet_id   = module.network[0].workload_subnet_id

  depends_on = [google_project_service.required]
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

  depends_on = [google_project_service.required]
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

  depends_on = [google_project_service.required]
}
