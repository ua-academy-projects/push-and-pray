resource "google_service_account" "vm" {
  for_each     = local.gcp_vms
  account_id   = "${local.resource_prefix}-${each.key}"
  display_name = "${local.resource_prefix}-${each.key}"
  description  = "Runtime identity for the ${local.resource_prefix}-${each.key} workload VM"
}

resource "google_project_iam_member" "vm_monitoring_metric_writer" {
  for_each = local.gcp_vms

  project = var.config.clouds.gcp.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.vm[each.key].email}"
}

resource "google_project_iam_member" "vm_logging_writer" {
  for_each = local.gcp_vms

  project = var.config.clouds.gcp.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vm[each.key].email}"
}
