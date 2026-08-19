resource "google_project_service" "secretmanager" {
  project = local.config.project_id
  service = "secretmanager.googleapis.com"

  disable_on_destroy = false
}
