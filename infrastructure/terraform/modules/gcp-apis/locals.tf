locals {
  cloud_name = "gcp"
  vms = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == local.cloud_name
  }
  base_required_apis = [
    "compute.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "secretmanager.googleapis.com",
  ]
  managed_database_apis = [
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
  ]
  required_apis = concat(
    local.base_required_apis,
    var.enable_managed_database ? local.managed_database_apis : [],
  )
}
