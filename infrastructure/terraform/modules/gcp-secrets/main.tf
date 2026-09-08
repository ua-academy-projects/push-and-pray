resource "google_secret_manager_secret" "this" {
  for_each = local.secret_ids

  project   = var.config.cloud_settings.gcp.project_id
  secret_id = each.value
  labels    = local.context.labels

  replication {
    auto {}
  }
}

resource "google_service_account" "vm" {
  for_each = local.vms

  project      = var.config.cloud_settings.gcp.project_id
  account_id   = "${local.context.resource_prefix}-${each.key}"
  display_name = "${local.context.resource_prefix}-${each.key}"
}

resource "google_secret_manager_secret_iam_member" "vm" {
  for_each = local.secret_access

  project   = var.config.cloud_settings.gcp.project_id
  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.vm[each.value.vm_name].member
}
