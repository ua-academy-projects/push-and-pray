data "google_compute_zones" "available" {
  depends_on = [google_project_service.required]
  count      = local.enabled ? 1 : 0

  project = var.config.clouds.gcp.project_id
  region  = local.region
  status  = "UP"
}