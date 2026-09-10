resource "google_compute_global_address" "ip_address" {
  name          = var.resource_prefix
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.network_id
}

resource "google_service_networking_connection" "default" {
  network = var.network_id
  service = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [
    google_compute_global_address.ip_address.name
  ]
}

resource "google_sql_database_instance" "main" {
  name             = "${var.resource_prefix}-postgres"
  database_version = var.managed_settings.database_version
  region           = var.region

  settings {
    tier = var.managed_settings.tier

    database_flags {
      name  = "cloudsql.enable_pg_cron"
      value = "on"
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
    }
  }

  depends_on = [google_service_networking_connection.default]
}

resource "google_sql_database" "database" {
  name     = var.database.name
  instance = google_sql_database_instance.main.name
  project  = var.project_id
}

resource "google_sql_user" "database_user" {
  project             = var.project_id
  name                = var.database.user
  instance            = google_sql_database_instance.main.name
  password_wo         = var.managed_database_password
  password_wo_version = var.managed_database_password_version
}
