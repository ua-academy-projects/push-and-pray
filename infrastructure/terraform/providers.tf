provider "google" {
  project               = local.config.clouds.gcp.project_id
  region                = local.config.regions[local.config.default_region].gcp.region
  zone                  = local.config.regions[local.config.default_region].gcp.zone
  billing_project       = local.config.clouds.gcp.project_id
  user_project_override = true
}
provider "aws" {
  region = local.config.regions[local.config.default_region].aws.region
}
