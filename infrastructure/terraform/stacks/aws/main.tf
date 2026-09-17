locals {
  config = jsondecode(file(var.project_config_path))
}

provider "aws" {
  region = local.config.clouds.aws.locations[local.config.defaults.location_profile].region
}

module "aws" {
  source = "../../modules/aws"

  project_config_path          = var.project_config_path
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  database_password            = var.database_password
}

module "dns" {
  source = "../../modules/cloudflare-dns"

  zone_id      = var.cloudflare_zone_id
  hostname     = local.config.vms.ui.public_endpoint.hostname
  ipv4_address = module.aws.vms.ui.public_address
  proxied      = try(local.config.vms.ui.public_endpoint.proxied, false)
  ttl          = try(local.config.vms.ui.public_endpoint.ttl, 60)
}

module "deployment_contract" {
  source = "../../modules/deployment-contract"

  project_config_path    = var.project_config_path
  provider_name          = "aws"
  nodes                  = module.aws.vms
  managed_database       = module.aws.managed_database
  managed_service_images = module.aws.managed_service_images
  monitoring             = module.aws.monitoring
  dns                    = module.dns.record
}
