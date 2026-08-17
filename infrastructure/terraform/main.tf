# Root Terraform module.
#
# Network and bastion resources will be added in issue #13.
module "network" {
  source = "./modules/network"

  project_id            = var.project_id
  region                = var.region
}

module "bastion" {
  source        = "./modules/bastion"
  project_id    = var.project_id
  zone          = var.zone

  subnetwork_id = module.network.public_subnet
  network_tag   = module.network.network_tags.bastion
}
# Application compute resources will be added in issue #14.

