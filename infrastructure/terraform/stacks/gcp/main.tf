locals {
  config = jsondecode(file(var.project_config_path))
}

provider "google" {
  project = local.config.clouds.gcp.project_id
  region  = local.config.clouds.gcp.locations[local.config.defaults.location_profile].region
  zone    = local.config.clouds.gcp.locations[local.config.defaults.location_profile].zone
}

module "gcp" {
  source = "../../modules/gcp"

  project_config_path          = var.project_config_path
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  secret_version_managers      = var.secret_version_managers
  database_password            = var.database_password
}

module "dns" {
  source = "../../modules/cloudflare-dns"

  zone_id      = var.cloudflare_zone_id
  hostname     = local.config.vms.ui.public_endpoint.hostname
  ipv4_address = module.gcp.vms.ui.public_address
  proxied      = try(local.config.vms.ui.public_endpoint.proxied, false)
  ttl          = try(local.config.vms.ui.public_endpoint.ttl, 60)
}

module "deployment_contract" {
  source = "../../modules/deployment-contract"

  project_config_path    = var.project_config_path
  provider_name          = "gcp"
  nodes                  = module.gcp.vms
  managed_database       = module.gcp.managed_database
  application_images     = module.gcp.application_images
  cloud_registry         = module.gcp.registry
  managed_service_images = module.gcp.managed_service_images
  monitoring             = module.gcp.monitoring
  dns                    = module.dns.record
}
