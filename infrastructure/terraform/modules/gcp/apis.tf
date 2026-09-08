locals {
  required_apis = concat(
    [
      "cloudresourcemanager.googleapis.com",
      "compute.googleapis.com",
      "iam.googleapis.com",
      "secretmanager.googleapis.com",
    ],
    local.monitoring_enabled ? [
      "logging.googleapis.com",
      "monitoring.googleapis.com",
    ] : [],
    local.monitoring_enabled && local.monitoring_settings.budget.enabled ? [
      "billingbudgets.googleapis.com",
    ] : [],
  )
}

resource "google_project_service" "required" {
  for_each = local.has_vms ? toset(local.required_apis) : toset([])

  service = each.value

  disable_on_destroy         = false
  disable_dependent_services = false
}
