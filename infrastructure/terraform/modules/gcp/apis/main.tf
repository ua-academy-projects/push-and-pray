resource "google_project_service" "required" {
  for_each = var.enabled ? toset(local.required_apis) : toset([])

  service = each.value

  disable_on_destroy         = false
  disable_dependent_services = false
}
