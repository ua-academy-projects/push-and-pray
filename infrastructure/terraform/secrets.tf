resource "google_secret_manager_secret" "deployment" {
  for_each = local.deployment_secrets

  secret_id = each.value.secret_id
  labels    = local.common_labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = local.secret_access_bindings

  secret_id = google_secret_manager_secret.deployment[each.value.secret_key].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm[each.value.role].email}"
}
