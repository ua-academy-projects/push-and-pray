provider "google" {
  project = local.config.clouds.gcp.project_id
  region  = local.default_location.gcp.region
  zone    = local.default_location.gcp.zone
}

provider "aws" {
  region              = local.default_location.aws.region
  allowed_account_ids = [local.config.clouds.aws.account_id]
}
