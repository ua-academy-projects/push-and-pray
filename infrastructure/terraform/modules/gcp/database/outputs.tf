output "connection" {
  description = "Cloud SQL connection metadata and administrator secret reference; null when disabled. Never contains password values."
  value = local.enabled ? {
    host                     = local.dns_name
    port                     = 5432 # Cloud SQL PostgreSQL's fixed listener port.
    database                 = google_sql_database.application[0].name
    admin_username           = google_sql_user.admin[0].name
    admin_secret_id          = google_secret_manager_secret.admin[0].id
    instance_connection_name = google_sql_database_instance.this[0].connection_name
    sslmode                  = "verify-full"
    ca_bundle_url            = "https://storage.googleapis.com/cloudsql-ca-bundles/${local.region}.pem"
  } : null
  depends_on = [google_dns_record_set.database, google_secret_manager_secret_version.admin]
}

output "monitoring" {
  value = local.enabled ? {
    id         = "${var.config.clouds.gcp.project_id}:${google_sql_database_instance.this[0].name}"
    project_id = var.config.clouds.gcp.project_id
  } : null
}
