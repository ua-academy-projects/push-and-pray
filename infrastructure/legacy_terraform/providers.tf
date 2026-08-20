provider "google" {
  project = local.config.project_id
  region  = local.config.region
  zone    = local.config.zone
}
