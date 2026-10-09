module "network" {
  source = "./network"

  has_selected_vms           = local.has_selected_vms
  managed_kubernetes_enabled = local.managed_kubernetes_enabled
  config                     = var.config
}

module "routing" {
  source           = "./routing"
  has_selected_vms = local.has_selected_vms

  config             = var.config
  network_id         = module.network.network_id
  workload_subnet_id = module.network.workload_subnet_id
}

module "firewall" {
  source           = "./firewall"
  has_selected_vms = local.has_selected_vms

  config       = var.config
  selected_vms = local.selected_vms
  network_id   = module.network.network_id
  network_tags = module.network.network_tags
}

module "gke" {
  source = "./gke"

  config              = var.config
  enabled             = local.managed_kubernetes_enabled
  network_id          = module.network.network_id
  workload_subnet_id  = module.network.workload_subnet_id
  pods_range_name     = module.network.gke_pods_range_name
  services_range_name = module.network.gke_services_range_name
  network_tags        = module.network.network_tags
  authorized_cidrs    = try(local.selected_vms.bastion.allowed_cidrs, [])

  depends_on = [module.routing]
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
  service_account_emails = module.iam.service_account_emails
  public_ips             = module.addresses.public_ips
}

module "secrets" {
  source = "./secrets"

  config                  = var.config
  selected_vms            = local.selected_vms
  service_account_emails  = module.iam.service_account_emails
  secret_version_managers = var.secret_version_managers
}

module "monitoring" {
  source = "./monitoring"

  config           = var.config
  selected_vms     = local.selected_vms
  has_selected_vms = local.has_selected_vms
  instance_ids     = module.vm.ids
}

module "cloud_sql" {
  source = "./cloud_sql"

  config                = var.config
  has_selected_vms      = local.has_selected_vms
  network_self_link     = module.network.network_self_link
  db_password_secret_id = try(module.secrets.secret_resource_names[local.db_password_secret_id], null)

  depends_on = [module.network, module.secrets]
}

resource "random_password" "postgres" {
  count   = local.has_selected_vms && !local.managed_db_enabled && local.db_password_secret_id != null ? 1 : 0
  length  = 32
  special = false
}

resource "google_secret_manager_secret_version" "postgres" {
  count = local.has_selected_vms && !local.managed_db_enabled && local.db_password_secret_id != null ? 1 : 0

  secret      = module.secrets.secret_resource_names[local.db_password_secret_id]
  secret_data = random_password.postgres[0].result
}

resource "random_password" "rabbitmq" {
  count   = local.has_selected_vms ? 1 : 0
  length  = 32
  special = false
}

resource "google_secret_manager_secret_version" "rabbitmq" {
  count = local.has_selected_vms && local.rabbitmq_password_secret_id != null ? 1 : 0

  secret      = module.secrets.secret_resource_names[local.rabbitmq_password_secret_id]
  secret_data = random_password.rabbitmq[0].result
}

resource "random_password" "redis" {
  count   = local.has_selected_vms ? 1 : 0
  length  = 32
  special = false
}

resource "google_secret_manager_secret_version" "redis" {
  count = local.has_selected_vms && local.redis_password_secret_id != null ? 1 : 0

  secret      = module.secrets.secret_resource_names[local.redis_password_secret_id]
  secret_data = random_password.redis[0].result
}
resource "random_password" "grafana" {
  count   = local.has_selected_vms && local.grafana_password_secret_id != null ? 1 : 0
  length  = 32
  special = false
}

resource "google_secret_manager_secret_version" "grafana" {
  count = local.has_selected_vms && local.grafana_password_secret_id != null ? 1 : 0

  secret      = module.secrets.secret_resource_names[local.grafana_password_secret_id]
  secret_data = random_password.grafana[0].result
}
