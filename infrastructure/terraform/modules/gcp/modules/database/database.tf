# The managed PostgreSQL. Reached only through a Private Service Connect
# endpoint in the database subnet: no public address, no peering, and TLS on
# every connection. The application role is not created here - Ansible does
# that with a password Terraform never sees.
resource "google_sql_database_instance" "main" {
  name             = local.name
  region           = var.region
  database_version = "POSTGRES_${var.settings.engine_version}"

  deletion_protection = var.settings.deletion_protection

  settings {
    tier = var.tier
    # Shared-core tiers such as db-f1-micro exist only in this edition.
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = var.settings.storage_gb
    disk_autoresize   = true
    user_labels       = var.labels

    deletion_protection_enabled = var.settings.deletion_protection

    backup_configuration {
      enabled                        = local.backups_enabled
      point_in_time_recovery_enabled = local.backups_enabled
      start_time                     = "02:00"
      transaction_log_retention_days = local.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = max(var.settings.backup_retention_days, 1)
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled = false
      ssl_mode     = "ENCRYPTED_ONLY"

      psc_config {
        psc_enabled               = true
        allowed_consumer_projects = [var.project_id]
      }
    }
  }
}

resource "google_sql_database" "application" {
  name     = var.settings.name
  instance = google_sql_database_instance.main.name

  # Destroying the instance takes the database with it; there is no reason to
  # drop it separately first, and the provider cannot while users still exist.
  deletion_policy = "ABANDON"
}

# The consumer side of Private Service Connect: an address of our own in the
# database subnet, and a forwarding rule that ties it to the instance's
# service attachment. Workloads connect to this address.
resource "google_compute_address" "endpoint" {
  name         = "${local.name}-endpoint"
  region       = var.region
  subnetwork   = var.subnet_id
  address_type = "INTERNAL"
  labels       = var.labels
}

resource "google_compute_forwarding_rule" "endpoint" {
  name                  = "${local.name}-endpoint"
  region                = var.region
  network               = var.network_id
  ip_address            = google_compute_address.endpoint.id
  target                = google_sql_database_instance.main.psc_service_attachment_link
  load_balancing_scheme = ""

  allow_psc_global_access = false
}
