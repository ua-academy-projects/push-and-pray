locals {
  instance_name = "${var.resource_prefix}-postgres-${var.generation}"
  cidr_parts    = split("/", var.private_service_cidr)
}

resource "google_compute_global_address" "private_services" {
  name          = "${var.resource_prefix}-database-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = cidrhost(var.private_service_cidr, 0)
  prefix_length = tonumber(local.cidr_parts[1])
  network       = var.network_id
}

resource "google_service_networking_connection" "private_services" {
  network                 = var.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}

resource "google_compute_network_peering_routes_config" "private_services" {
  peering              = google_service_networking_connection.private_services.peering
  network              = var.network_id
  import_custom_routes = true
  export_custom_routes = true
}

resource "google_sql_database_instance" "this" {
  name             = local.instance_name
  project          = var.project_id
  region           = var.region
  database_version = var.engine_version

  deletion_protection = var.deletion_protection

  settings {
    tier              = var.tier
    availability_type = var.availability_type
    disk_size         = var.disk_size_gb
    disk_type         = "PD_SSD"
    disk_autoresize   = true
    user_labels       = var.labels

    ip_configuration {
      ipv4_enabled       = false
      private_network    = var.network_id
      allocated_ip_range = google_compute_global_address.private_services.name
    }

    dynamic "backup_configuration" {
      for_each = var.backups_enabled ? [true] : []
      content {
        enabled                        = true
        point_in_time_recovery_enabled = true
      }
    }

    dynamic "final_backup_config" {
      for_each = var.backup_on_delete ? [true] : []
      content {
        enabled        = true
        retention_days = 30
      }
    }
  }

  dynamic "restore_backup_context" {
    for_each = var.backup_run_id == null ? [] : [var.backup_run_id]
    content {
      backup_run_id = restore_backup_context.value
    }
  }

  depends_on = [google_service_networking_connection.private_services]

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_sql_database" "this" {
  name     = var.database_name
  project  = var.project_id
  instance = google_sql_database_instance.this.name
}

resource "google_sql_user" "this" {
  name     = var.username
  project  = var.project_id
  instance = google_sql_database_instance.this.name
  password = var.password
}
