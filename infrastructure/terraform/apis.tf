locals {
  required_apis = [
    "compute.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
  ]
}

resource "google_project_service" "required" {
  for_each = toset(local.has_gcp ? local.required_apis : [])

  service = each.value

  disable_on_destroy         = false
  disable_dependent_services = false
}

moved {
  from = google_project_service.secretmanager
  to   = google_project_service.required["secretmanager.googleapis.com"]
}
