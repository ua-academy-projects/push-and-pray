locals {
  monitoring_enabled         = try(var.config.monitoring.enabled, true)
  monitoring_metrics_enabled = local.monitoring_enabled && try(var.config.monitoring.agent_metrics_enabled, false)
  monitoring_logs_enabled    = local.monitoring_enabled && try(var.config.monitoring.logs_enabled, true)
}
resource "google_project_iam_member" "monitoring_metrics" {
  for_each = { for name, vm in local.gcp_vms : name => vm if local.monitoring_metrics_enabled }
  project  = var.config.clouds.gcp.project_id
  role     = "roles/monitoring.metricWriter"
  member   = "serviceAccount:${google_service_account.workload[each.key].email}"
}
resource "google_project_iam_member" "monitoring_logs" {
  for_each = { for name, vm in local.gcp_vms : name => vm if local.monitoring_logs_enabled && vm.role == "ui" }
  project  = var.config.clouds.gcp.project_id
  role     = "roles/logging.logWriter"
  member   = "serviceAccount:${google_service_account.workload[each.key].email}"
}
