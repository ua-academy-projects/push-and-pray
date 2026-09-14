resource "google_project_service" "database" {
  for_each = local.enabled ? toset([
    "sqladmin.googleapis.com", "secretmanager.googleapis.com", "dns.googleapis.com"
  ]) : toset([])
  project = var.config.clouds.gcp.project_id
  service = each.value
  # These project-wide APIs can serve resources outside this module.
  disable_on_destroy = false
}

resource "google_sql_database_instance" "this" {
  count               = local.enabled ? 1 : 0
  name                = "${local.resource_prefix}-database"
  project             = var.config.clouds.gcp.project_id
  region              = local.region
  database_version    = local.settings.database_version
  deletion_protection = false

  settings {
    tier                        = local.settings.tier
    edition                     = local.settings.edition
    disk_size                   = local.settings.disk_size_gb
    disk_type                   = local.settings.disk_type
    disk_autoresize             = local.settings.disk_autoresize
    availability_type           = local.settings.availability_type
    deletion_protection_enabled = false
    retain_backups_on_delete    = false
    user_labels                 = local.labels

    location_preference {
      zone = var.config.region_map[var.config.region].gcp.zone
    }
    ip_configuration {
      ipv4_enabled                     = false
      private_network                  = var.network.cloud_sql.network_id
      allocated_ip_range               = var.network.cloud_sql.allocated_range_name
      ssl_mode                         = "ENCRYPTED_ONLY"
      server_ca_mode                   = "GOOGLE_MANAGED_CAS_CA"
      server_certificate_rotation_mode = "AUTOMATIC_ROTATION_DURING_MAINTENANCE"
    }
    backup_configuration {
      enabled = true
      # HA requires PITR; the economy ZONAL profile does not enable it.
      point_in_time_recovery_enabled = local.settings.availability_type == "REGIONAL"
      backup_retention_settings {
        retained_backups = local.settings.backup_retained_count
        retention_unit   = "COUNT"
      }
    }
    final_backup_config {
      enabled = false
    }
  }
  depends_on = [google_project_service.database]
}

resource "google_sql_database" "application" {
  count    = local.enabled ? 1 : 0
  project  = var.config.clouds.gcp.project_id
  instance = google_sql_database_instance.this[0].name
  name     = "oil_tracker"
  # The containing instance is destroyed at mode switch; do not DROP a live DB first.
  deletion_policy = "ABANDON"
}
