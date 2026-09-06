provider "google" {
  project = try(local.config.clouds.gcp.project_id, null)
  region  = try(local.config.clouds.gcp.region, null)
  zone    = try(local.config.clouds.gcp.zone, null)
}