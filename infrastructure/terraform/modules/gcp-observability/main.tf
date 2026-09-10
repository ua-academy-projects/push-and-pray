resource "google_project_iam_member" "ops_agent" {
  for_each = local.service_account_roles

  project = var.config.cloud_settings.gcp.project_id
  role    = each.value.role
  member  = "serviceAccount:${each.value.email}"
}
