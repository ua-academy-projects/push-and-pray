provider "google" {
  project = local.config.clouds.gcp.project_id
  region  = local.config.regions[local.config.default_region].gcp.region
  zone    = local.config.regions[local.config.default_region].gcp.zone
}
provider "aws" {
  region = local.config.regions[local.config.default_region].aws.region
}
