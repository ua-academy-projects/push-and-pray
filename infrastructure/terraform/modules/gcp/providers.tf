provider "google" {
  project = try(var.config.clouds.gcp.project_id, null)
  region  = local.region
}