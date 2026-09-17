resource "google_project_service" "monitoring" {
  for_each           = (local.enabled || local.budget_enabled) ? toset(["monitoring.googleapis.com", "logging.googleapis.com"]) : toset([])
  project            = local.project_id
  service            = each.value
  disable_on_destroy = false
}
