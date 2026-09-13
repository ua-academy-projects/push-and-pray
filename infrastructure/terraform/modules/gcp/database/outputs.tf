output "database" {
  description = "Non-secret Cloud SQL connection metadata."
  value = local.enabled ? {
    provider            = "gcp"
    host                = google_sql_database_instance.postgres[0].private_ip_address
    port                = var.config.database.port
    name                = google_sql_database.application[0].name
    admin_user          = var.config.database.admin_user
    admin_secret_arn    = null
    instance_name       = google_sql_database_instance.postgres[0].name
    sslmode             = "require"
    publicly_accessible = false
  } : null
}

output "enabled" {
  description = "Whether this provider-specific managed database is selected."
  value       = local.enabled
}
