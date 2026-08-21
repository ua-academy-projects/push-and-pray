resource "google_secret_manager_secret_iam_member" "publisher" {
  for_each = var.secret_ids

  secret_id = each.value
  role      = "roles/secretmanager.secretVersionAdder"
  member    = "serviceAccount:${var.publisher_service_account}"
}