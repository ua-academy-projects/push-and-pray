resource "google_project_service" "required" {
  for_each = length(local.vms) > 0 ? toset(local.required_apis) : toset([])

  service = each.value

  disable_on_destroy         = false
  disable_dependent_services = false
}
