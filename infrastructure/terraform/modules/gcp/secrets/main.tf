resource "google_secret_manager_secret" "this" {
  for_each  = var.secret_ids
  secret_id = each.value
  labels    = var.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "workload_access" {
  for_each = {
    for pair in local.workload_secret_pairs :
    "${pair.vm_name}/${pair.secret_id}" => pair
  }

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${each.value.service_account_email}"
}

resource "google_secret_manager_secret_iam_member" "version_adder" {
  for_each = local.secret_version_writers

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = each.value.member
}

resource "google_secret_manager_secret_version" "managed" {
  # Secret IDs are configuration, not credentials. Only expose them to
  # for_each; index the original sensitive map below to keep the payload
  # sensitive in plans and state output.
  for_each = toset(nonsensitive(keys(var.secret_values)))

  secret      = google_secret_manager_secret.this[each.key].id
  secret_data = var.secret_values[each.key]
}
