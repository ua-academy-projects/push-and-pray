resource "google_secret_manager_secret" "managed" {
  for_each = var.secret_ids

  secret_id = each.value
  labels    = var.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = {
    for item in flatten([
      for secret_id, service_accounts in var.accessors : [
        for service_account in service_accounts : {
          key             = "${secret_id}:${service_account}"
          secret_id       = secret_id
          service_account = service_account
        }
      ]
    ]) : item.key => item
  }

  secret_id = google_secret_manager_secret.managed[each.value.secret_id].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${each.value.service_account}"
}