resource "google_secret_manager_secret" "this" {
  for_each  = toset(local.all_secret_ids)
  secret_id = each.value
  labels    = local.common_tags

  replication {
    auto {}
  }
}

resource "random_password" "generated" {
  for_each = toset(var.generated_secret_ids)

  length  = 32
  special = false

  lifecycle {
    precondition {
      condition     = contains(local.all_secret_ids, each.key)
      error_message = "Every generated secret ID must exist in a workload secret mapping."
    }
  }
}

resource "google_secret_manager_secret_version" "generated" {
  for_each = toset(var.generated_secret_ids)

  secret      = google_secret_manager_secret.this[each.key].id
  secret_data = random_password.generated[each.key].result
}

resource "google_secret_manager_secret_iam_member" "workload_access" {
  for_each = {
    for pair in local.workload_secret_pairs :
    "${pair.vm_name}/${pair.secret_id}" => pair
  }

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.service_account_emails[each.value.vm_name]}"
}

resource "google_secret_manager_secret_iam_member" "version_adder" {
  for_each = local.secret_version_writers

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = each.value.member
}
