resource "google_project_iam_member" "agents" {
  for_each = local.grants

  project = var.config.gcp.project_id
  role    = each.value.role
  member  = "serviceAccount:${var.service_account_emails[each.value.account_name]}"
}

resource "google_logging_project_bucket_config" "default" {
  project        = var.config.gcp.project_id
  location       = "global"
  bucket_id      = "_Default"
  retention_days = var.config.monitoring.log_retention_days
}
