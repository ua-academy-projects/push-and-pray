provider "google" {
  project               = local.config.clouds.gcp.project_id
  region                = local.config.locations[local.config.default_location].gcp.region
  zone                  = local.config.locations[local.config.default_location].gcp.zone
  billing_project       = local.config.clouds.gcp.project_id
  user_project_override = true
}

provider "aws" {
  region              = local.config.locations[local.config.default_location].aws.region
  allowed_account_ids = [local.config.clouds.aws.account_id]
}
