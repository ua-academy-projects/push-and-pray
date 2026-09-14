resource "random_password" "admin" {
  count   = local.enabled ? 1 : 0
  length  = 32
  special = false
}

resource "google_sql_user" "admin" {
  count    = local.enabled ? 1 : 0
  project  = var.config.clouds.gcp.project_id
  instance = google_sql_database_instance.this[0].name
  name     = "oil_tracker_admin"
  password = random_password.admin[0].result
  # Role ownership must not prevent destruction of the containing instance.
  deletion_policy = "ABANDON"
}

resource "google_secret_manager_secret" "admin" {
  count     = local.enabled ? 1 : 0
  project   = var.config.clouds.gcp.project_id
  secret_id = "${local.resource_prefix}-database-admin"
  labels    = local.labels
  replication {
    auto {}
  }
  depends_on = [google_project_service.database]
}

resource "google_secret_manager_secret_version" "admin" {
  count  = local.enabled ? 1 : 0
  secret = google_secret_manager_secret.admin[0].id
  secret_data = jsonencode({
    username = google_sql_user.admin[0].name
    password = random_password.admin[0].result
  })
}
