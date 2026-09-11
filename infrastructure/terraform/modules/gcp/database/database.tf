resource "google_sql_database_instance" "main" {
  count = local.enabled

  name             = "${local.prefix}-database"
  region           = local.region
  database_version = "POSTGRES_${local.settings.engine_version}"

  deletion_protection = lookup(local.settings, "deletion_protection", false)

  settings {
    tier              = local.tier
    edition           = local.edition
    availability_type = "ZONAL"
    disk_size         = local.settings.storage_gb
    disk_type         = "PD_SSD"
    disk_autoresize   = true
    user_labels       = local.labels

    backup_configuration {
      enabled                        = lookup(local.settings, "backup_retention_days", 7) > 0
      point_in_time_recovery_enabled = lookup(local.settings, "backup_retention_days", 7) > 0
      start_time                     = "02:00"

      transaction_log_retention_days = min(max(lookup(local.settings, "backup_retention_days", 7), 1), 7)

      backup_retention_settings {
        retained_backups = max(lookup(local.settings, "backup_retention_days", 7), 1)
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled = false

      psc_config {
        psc_enabled               = true
        allowed_consumer_projects = [local.project_id]
      }
    }

    deletion_protection_enabled = lookup(local.settings, "deletion_protection", false)

    dynamic "database_flags" {
      for_each = local.flags

      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  lifecycle {
    precondition {
      condition     = local.tier != null
      error_message = "The catalog has no gcp db_size mapping for ${lookup(local.settings, "size", "micro")}."
    }

    precondition {
      condition     = local.project_id != ""
      error_message = "A managed database on GCP needs gcp.project_id in the project configuration."
    }
  }
}

resource "google_sql_database" "application" {
  count = local.enabled

  name     = local.settings.database_name
  instance = google_sql_database_instance.main[0].name

  deletion_policy = "ABANDON"
}
