module "network" {
  source = "./network"
  count  = local.has_vms ? 1 : 0

  resource_prefix = local.resource_prefix
  region          = local.config.regions[local.config.default_region][local.cloud_key].region

  management_subnet_cidr = local.config.network.management_subnet_cidr
  workload_subnet_cidr   = local.config.network.workload_subnet_cidr

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

moved {
  from = module.network[0].google_compute_firewall.bastion_ssh
  to   = module.security[0].google_compute_firewall.bastion_ssh
}

moved {
  from = module.network[0].google_compute_firewall.bastion_ssh_bootstrap
  to   = module.security[0].google_compute_firewall.bastion_ssh_bootstrap
}

moved {
  from = module.network[0].google_compute_firewall.workload_ssh
  to   = module.security[0].google_compute_firewall.workload_ssh
}

moved {
  from = module.network[0].google_compute_firewall.ui_web
  to   = module.security[0].google_compute_firewall.ui_web
}

moved {
  from = module.network[0].google_compute_firewall.history_api
  to   = module.security[0].google_compute_firewall.history_api
}

moved {
  from = module.network[0].google_compute_firewall.postgresql
  to   = module.security[0].google_compute_firewall.postgresql
}

moved {
  from = google_secret_manager_secret.this
  to   = module.secrets.google_secret_manager_secret.this
}

moved {
  from = google_secret_manager_secret_iam_member.workload_access
  to   = module.secrets.google_secret_manager_secret_iam_member.workload_access
}

moved {
  from = google_secret_manager_secret_iam_member.version_adder
  to   = module.secrets.google_secret_manager_secret_iam_member.version_adder
}

moved {
  from = module.vm["bastion"].google_service_account.workload
  to   = module.vm[0].google_service_account.workload["bastion"]
}

moved {
  from = module.vm["infra"].google_service_account.workload
  to   = module.vm[0].google_service_account.workload["infra"]
}

moved {
  from = module.vm["history"].google_service_account.workload
  to   = module.vm[0].google_service_account.workload["history"]
}

moved {
  from = module.vm["fetcher"].google_service_account.workload
  to   = module.vm[0].google_service_account.workload["fetcher"]
}

moved {
  from = module.vm["ui"].google_service_account.workload
  to   = module.vm[0].google_service_account.workload["ui"]
}

moved {
  from = module.vm["bastion"].google_compute_address.public[0]
  to   = module.vm[0].google_compute_address.public["bastion"]
}

moved {
  from = module.vm["ui"].google_compute_address.public[0]
  to   = module.vm[0].google_compute_address.public["ui"]
}

moved {
  from = module.vm["bastion"].google_compute_instance.workload
  to   = module.vm[0].google_compute_instance.workload["bastion"]
}

moved {
  from = module.vm["infra"].google_compute_instance.workload
  to   = module.vm[0].google_compute_instance.workload["infra"]
}

moved {
  from = module.vm["history"].google_compute_instance.workload
  to   = module.vm[0].google_compute_instance.workload["history"]
}

moved {
  from = module.vm["fetcher"].google_compute_instance.workload
  to   = module.vm[0].google_compute_instance.workload["fetcher"]
}

moved {
  from = module.vm["ui"].google_compute_instance.workload
  to   = module.vm[0].google_compute_instance.workload["ui"]
}
