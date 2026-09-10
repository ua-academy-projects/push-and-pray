module "network" {
  source = "./network"

  has_selected_vms = local.has_selected_vms
  config = var.config
}

module "routing" {
  source = "./routing"
  has_selected_vms = local.has_selected_vms

  config              = var.config
  network_id          = module.network.network_id
  workload_subnet_id  = module.network.workload_subnet_id
}

module "firewall" {
  source = "./firewall"
  has_selected_vms = local.has_selected_vms

  config       = var.config
  network_id   = module.network.network_id
  network_tags = module.network.network_tags
}

module "iam" {
  source = "./iam"

  config = var.config
}

module "addresses" {
  source = "./addresses"

  config = var.config
}

module "vm" {
  source = "./vm"

  config = var.config

  management_subnet_id   = module.network.management_subnet_id
  workload_subnet_id     = module.network.workload_subnet_id
  service_account_emails = module.iam.service_account_emails
  public_ips              = module.addresses.public_ips
}

module "secrets" {
  source = "./secrets"

  config                  = var.config
  service_account_emails  = module.iam.service_account_emails
  secret_version_managers = var.secret_version_managers
}

module "monitoring" {
  source = "./monitoring"

  config = var.config
  has_selected_vms = local.has_selected_vms
  instance_ids = module.vm.ids
}

module "cloud_sql" {
  source = "./cloud_sql"

  config = var.config
  has_selected_vms = local.has_selected_vms
  network_self_link = module.network.network_self_link
  db_password_secret_id = try(module.secrets.secret_resource_names[local.db_password_secret_id], null)

  depends_on = [module.network, module.secrets]
}