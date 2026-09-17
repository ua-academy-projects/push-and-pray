locals {
  common_labels = merge(var.labels, {
    managed_by = "terraform"
    service    = "postgresql"
  })
}

resource "google_compute_global_address" "private_service_range" {
  count = var.enabled ? 1 : 0

  name          = "${var.name_prefix}-cloud-sql-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 24
  network       = var.network_id
}

resource "google_service_networking_connection" "private_vpc" {
  count = var.enabled ? 1 : 0

  network                 = var.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range[0].name]
}

resource "random_password" "database" {
  count = var.enabled ? 1 : 0

  length  = 32
  special = false
}

resource "google_sql_database_instance" "this" {
  count = var.enabled ? 1 : 0

  name             = "${var.name_prefix}-postgres"
  project          = var.project_id
  region           = var.region
  database_version = var.database_version

  settings {
    tier              = var.tier
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = var.disk_size
    disk_autoresize   = true
    user_labels       = local.common_labels

    database_flags {
      name  = "cloudsql.enable_pg_cron"
      value = "on"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 1
      backup_retention_settings {
        retained_backups = 1
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.network_id
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }
  }

  deletion_protection = var.deletion_protection

  depends_on = [google_service_networking_connection.private_vpc]

  lifecycle {
    precondition {
      condition     = var.clients_share_cloud
      error_message = "Cloud SQL clients must all select GCP until private cross-cloud routing exists."
    }
  }
}

resource "google_sql_database" "this" {
  count = var.enabled ? 1 : 0

  name     = var.database_name
  project  = var.project_id
  instance = google_sql_database_instance.this[0].name
}

resource "google_sql_user" "application" {
  count = var.enabled ? 1 : 0

  name     = var.username
  project  = var.project_id
  instance = google_sql_database_instance.this[0].name
  password = random_password.database[0].result
}

resource "google_secret_manager_secret" "credentials" {
  count = var.enabled ? 1 : 0

  project   = var.project_id
  secret_id = "${var.name_prefix}-managed-database"
  labels    = local.common_labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "credentials" {
  count = var.enabled ? 1 : 0

  secret = google_secret_manager_secret.credentials[0].id
  secret_data = jsonencode({
    username = var.username
    password = random_password.database[0].result
    host     = google_sql_database_instance.this[0].private_ip_address
    port     = 5432
    dbname   = var.database_name
  })
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = var.enabled ? var.secret_accessor_members : {}

  project   = var.project_id
  secret_id = google_secret_manager_secret.credentials[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value
}
