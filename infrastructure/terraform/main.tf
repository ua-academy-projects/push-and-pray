module "aws_network" {
  source = "./modules/aws-network"

  config = local.config
}

module "aws_security" {
  source = "./modules/aws-security"

  config   = local.config
  networks = module.aws_network.networks
}

module "aws_secrets" {
  source = "./modules/aws-secrets"

  config = local.config
}

module "aws_observability" {
  source = "./modules/aws-observability"

  config       = local.config
  instance_ids = module.aws_vm.instance_ids
  role_names   = module.aws_secrets.role_names
  volume_ids   = module.aws_vm.volume_ids
}

module "aws_vm" {
  source = "./modules/aws-vm"

  config             = local.config
  instance_profiles  = module.aws_secrets.instance_profile_names
  networks           = module.aws_network.networks
  security_group_ids = module.aws_security.security_group_ids
}

module "gcp_network" {
  source = "./modules/gcp-network"

  config = local.config
}

module "gcp_firewall" {
  source = "./modules/gcp-firewall"

  config   = local.config
  networks = module.gcp_network.networks
}

module "gcp_secrets" {
  source = "./modules/gcp-secrets"

  config = local.config
}

module "gcp_observability" {
  source = "./modules/gcp-observability"

  config                 = local.config
  instance_ids           = module.gcp_vm.instance_ids
  service_account_emails = module.gcp_secrets.service_account_emails
}

module "gcp_vm" {
  source = "./modules/gcp-vm"

  config                 = local.config
  networks               = module.gcp_network.networks
  service_account_emails = module.gcp_secrets.service_account_emails
}

module "aws_managed_database" {
  count  = local.config.database.mode == "managed" && local.config.default_cloud == "aws" ? 1 : 0
  source = "./modules/aws-managed-database"

  config  = local.config
  network = module.aws_network.networks[local.config.default_location]
  client_security_group_ids = compact([
    try(module.aws_security.security_group_ids[local.config.default_location].infrastructure, null),
    try(module.aws_security.security_group_ids[local.config.default_location].history, null),
  ])
  password = var.database_password
}

module "gcp_managed_database" {
  count  = local.config.database.mode == "managed" && local.config.default_cloud == "gcp" ? 1 : 0
  source = "./modules/gcp-managed-database"

  config     = local.config
  network_id = module.gcp_network.networks[local.config.default_location].network_id
  client_service_accounts = toset(compact([
    try(module.gcp_secrets.service_account_emails.infrastructure, null),
    try(module.gcp_secrets.service_account_emails.history, null),
  ]))
  password = var.database_password
}

module "cloudflare_dns" {
  count  = try(local.config.dns.cloudflare.zone_id, null) == null ? 0 : 1
  source = "./modules/cloudflare-dns"

  zone_id      = local.config.dns.cloudflare.zone_id
  hostname     = local.config.vms.ui.public_endpoint.hostname
  ipv4_address = merge(module.gcp_vm.public_ips, module.aws_vm.public_ips)["ui"]
}
