resource "random_password" "database" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret_version" "database_password" {
  secret      = var.password_secret_id
  secret_data = random_password.database.result
}

resource "google_sql_database_instance" "main" {
  name             = "${local.resource_prefix}-postgresql"
  region           = var.config.regions[var.config.location].gcp
  database_version = local.settings.database_version

  deletion_protection = var.config.environment == "prod"

  settings {
    tier              = local.settings.tier
    availability_type = local.settings.availability_type
    disk_size         = local.settings.disk_size_gb
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    backup_configuration {
      enabled = local.settings.backup_enabled
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.network_id
      enable_private_path_for_google_cloud_services = false
    }

    user_labels = var.config.common_labels
  }

  depends_on = [google_secret_manager_secret_version.database_password]
}

resource "google_sql_database" "application" {
  name     = var.config.services.database.name
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "application" {
  name     = var.config.services.database.username
  instance = google_sql_database_instance.main.name
  password = random_password.database.result
}
