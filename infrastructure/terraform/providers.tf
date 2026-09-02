provider "google" {
  project = local.config.clouds.gcp.project_id
  region  = local.default_provider_locations.gcp.region
  zone    = local.default_provider_locations.gcp.zone
}

provider "aws" {
  region              = local.default_provider_locations.aws.region
  allowed_account_ids = [local.config.clouds.aws.account_id]
}
