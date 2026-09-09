locals {
  base_required_apis = [
    "compute.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
  ]

  required_apis = concat(
    local.base_required_apis,
    local.monitoring.enabled && local.monitoring.cpu.enabled && length(local.gcp_placements) > 0
    ? ["monitoring.googleapis.com"]
    : [],
  )
}

resource "google_project_service" "required" {
  for_each = (
    length(local.gcp_placements) > 0
    ? toset(local.required_apis)
    : toset([])
  )

  service = each.value

  disable_on_destroy         = false
  disable_dependent_services = false
}

moved {
  from = google_project_service.secretmanager
  to   = google_project_service.required["secretmanager.googleapis.com"]
}
