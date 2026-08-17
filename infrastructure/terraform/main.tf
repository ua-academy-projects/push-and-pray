# Root Terraform module.
#
# Network and bastion resources will be added in issue #13.
module "network" {
  source = "./modules/network"

  project_id            = var.project_id
  region                = var.region
}
# Application compute resources will be added in issue #14.

