provider "google" {
  project = try(local.config.clouds.gcp.project_id, null)
  region  = local.config.region_map[local.config.region]["gcp"].region
  zone    = local.config.region_map[local.config.region]["gcp"].zone
}

provider "aws" {
  region = local.config.region_map[local.config.region]["aws"].region
}