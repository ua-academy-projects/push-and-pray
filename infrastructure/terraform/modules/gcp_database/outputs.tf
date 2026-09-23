output "connection" {
  description = "Non-secret PostgreSQL connection settings for Ansible."
  value = {
    host               = google_sql_database_instance.main.private_ip_address
    port               = var.config.services.database.port
    name               = google_sql_database.application.name
    username           = google_sql_user.application.name
    ssl_mode           = var.config.services.database.ssl_mode
    password_secret_id = var.config.services.database.password_secret_id
  }
}
