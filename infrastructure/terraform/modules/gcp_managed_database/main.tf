resource "google_compute_global_address" "private_service_range" {
  project       = var.project_id
  name          = "${var.resource_prefix}-sql-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.network_id
}

resource "google_service_networking_connection" "private_vpc" {
  network                 = var.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]
}

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = "${var.resource_prefix}-postgres"
  region              = var.region
  database_version    = "POSTGRES_16"
  deletion_protection = false

  settings {
    tier              = "db-f1-micro"
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 10
    disk_autoresize   = true

    database_flags {
      name  = "cloudsql.enable_pg_cron"
      value = "on"
    }

    database_flags {
      name  = "cron.database_name"
      value = var.database_name
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.network_id
      enable_private_path_for_google_cloud_services = true
    }

    user_labels = var.labels
  }

  depends_on = [google_service_networking_connection.private_vpc]
}

resource "google_sql_database" "application" {
  project  = var.project_id
  name     = var.database_name
  instance = google_sql_database_instance.this.name
}

resource "google_sql_user" "application" {
  project  = var.project_id
  name     = var.database_user
  instance = google_sql_database_instance.this.name
  password = var.password
}
