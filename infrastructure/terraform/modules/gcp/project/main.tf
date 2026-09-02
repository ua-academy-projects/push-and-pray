locals {
  gcp_vms = {
    for name, vm in var.config.vms : name => vm
    if try(vm.cloud, var.config.default_cloud) == "gcp"
  }

  required_apis = [
    "compute.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
  ]
}

resource "google_project_service" "required" {
  for_each = length(local.gcp_vms) > 0 ? toset(local.required_apis) : toset([])

  service = each.value

  disable_on_destroy         = false
  disable_dependent_services = false
}
