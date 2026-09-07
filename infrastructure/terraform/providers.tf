provider "google" {
  project = local.config.gcp.project_id
  region  = local.config.regions[local.config.location].gcp
}

provider "aws" {
  region = local.config.regions[local.config.location].aws
}
