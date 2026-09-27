variable "config" {
  type = any
}

locals {
  project = var.config.clouds.gcp.project_id
  region  = var.config.locations[var.config.default_location].gcp.region
  name    = "${var.config.name_prefix}-${var.config.environment}"
  server  = "${local.region}-docker.pkg.dev"
}

resource "google_project_service" "artifact_registry" {
  project            = local.project
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "app" {
  project       = local.project
  location      = local.region
  repository_id = local.name
  format        = "DOCKER"
  description   = "Private OilScope application images"
  labels        = merge(var.config.common_labels, { environment = var.config.environment })

  depends_on = [google_project_service.artifact_registry]
}

output "registry" {
  value = {
    cloud  = "gcp"
    name   = google_artifact_registry_repository.app.repository_id
    region = local.region
    server = local.server
    images = {
      for image in ["history", "fetcher", "ui"] : image => "${local.server}/${local.project}/${google_artifact_registry_repository.app.repository_id}/${image}"
    }
  }
}
