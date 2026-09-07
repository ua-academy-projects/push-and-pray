resource "google_service_account" "accounts" {
  for_each = local.service_accounts

  account_id   = "${local.resource_prefix}-${each.key}"
  display_name = "${local.resource_prefix}-${each.key}"
}

resource "google_secret_manager_secret" "secrets" {
  for_each = local.secret_ids

  secret_id = each.value
  labels    = var.config.common_labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "readers" {
  for_each = merge(
    {},
    [
      for account_name, account in local.service_accounts : {
        for secret_id in toset(values(account.secret_mappings)) :
        "${account_name}/${secret_id}" => {
          account_name = account_name
          secret_id    = secret_id
        }
      }
    ]...
  )

  secret_id = google_secret_manager_secret.secrets[each.value.secret_id].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.accounts[each.value.account_name].email}"
}

resource "google_secret_manager_secret_iam_member" "version_adders" {
  for_each = local.secret_version_writers

  secret_id = google_secret_manager_secret.secrets[each.value.secret_id].id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = each.value.member
}
