provider "aws" {
  region = local.config.locations[local.config.default_location].aws.region
}

provider "google" {
  project = local.config.cloud_settings.gcp.project_id
}
