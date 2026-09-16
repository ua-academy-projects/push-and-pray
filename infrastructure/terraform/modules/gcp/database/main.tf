locals {
  enabled    = var.config.database_mode == "managed" && var.config.default_cloud == "gcp"
  project_id = var.config.clouds.gcp.project_id
}

resource "terraform_data" "private_service_connection" {
  count = local.enabled ? 1 : 0
  input = var.private_service_connection
}

resource "google_sql_database_instance" "postgres" {
  count = local.enabled ? 1 : 0

  project             = local.project_id
  name                = "${var.config.name_prefix}-${var.config.environment}-postgres"
  region              = var.config.locations[var.config.default_location].gcp.region
  database_version    = "POSTGRES_${var.config.database.postgres_version}"
  deletion_protection = var.config.environment == "prod"

  settings {
    tier              = var.config.provider_mappings.database_sizes[var.config.database.size].gcp.tier
    availability_type = var.config.environment == "prod" ? "REGIONAL" : "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = var.config.database.storage_gb
    disk_autoresize   = true
    user_labels       = merge(var.config.common_labels, { environment = var.config.environment })

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = var.config.environment == "prod"
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.network_id
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }
  }

  depends_on = [terraform_data.private_service_connection]
}

resource "google_sql_database" "application" {
  count = local.enabled ? 1 : 0

  project  = local.project_id
  name     = var.config.database.name
  instance = google_sql_database_instance.postgres[0].name
}

resource "google_sql_user" "admin" {
  count = local.enabled ? 1 : 0

  project  = local.project_id
  name     = var.config.database.admin_user
  instance = google_sql_database_instance.postgres[0].name
}
