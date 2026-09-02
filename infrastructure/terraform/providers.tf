provider "google" {
  project = local.config.clouds.gcp.project_id
  region  = local.config.locations[local.config.vms.bastion.location].gcp.region
  zone    = local.config.locations[local.config.vms.bastion.location].gcp.zone
}

provider "aws" {
  region              = local.config.locations[local.config.vms.bastion.location].aws.region
  allowed_account_ids = [local.config.clouds.aws.account_id]
}
