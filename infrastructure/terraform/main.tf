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

  role_names = module.aws_secrets.role_names
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
  service_account_emails = module.gcp_secrets.service_account_emails
}

module "gcp_vm" {
  source = "./modules/gcp-vm"

  config                 = local.config
  networks               = module.gcp_network.networks
  service_account_emails = module.gcp_secrets.service_account_emails
}
