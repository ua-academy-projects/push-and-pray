locals {
  project         = var.config.cloud_settings.gcp.project_id
  region          = var.config.locations[var.config.default_location].gcp.region
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  labels = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }, var.config.common_labels)
  tiers = {
    micro  = "db-f1-micro"
    small  = "db-g1-small"
    medium = "db-custom-2-7680"
  }
  private_cidr = var.config.network.managed_database.gcp_private_service_cidr
}

resource "google_project_service" "sqladmin" {
  project            = local.project
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "service_networking" {
  project            = local.project
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_compute_global_address" "private_service_access" {
  project       = local.project
  name          = "${local.resource_prefix}-managed-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = split("/", local.private_cidr)[0]
  prefix_length = tonumber(split("/", local.private_cidr)[1])
  network       = var.network_id

  depends_on = [google_project_service.service_networking]
}

resource "google_service_networking_connection" "private" {
  network                 = var.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_access.name]
  deletion_policy         = var.config.environment == "dev" ? "REMOVE_PEERING" : "DELETE"
}

resource "google_sql_database_instance" "this" {
  project          = local.project
  name             = "${local.resource_prefix}-postgres"
  region           = local.region
  database_version = "POSTGRES_${var.config.database.version}"

  deletion_protection = var.config.environment != "dev"

  settings {
    tier                        = local.tiers[var.config.database.size]
    edition                     = "ENTERPRISE"
    availability_type           = "ZONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = var.config.database.storage_gb
    disk_autoresize             = true
    user_labels                 = local.labels
    deletion_protection_enabled = var.config.environment != "dev"

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = var.config.environment != "dev"
      point_in_time_recovery_enabled = var.config.environment != "dev"
    }
  }

  depends_on = [
    google_project_service.sqladmin,
    google_service_networking_connection.private,
  ]
}

resource "google_sql_database" "this" {
  project  = local.project
  name     = "oil_tracker"
  instance = google_sql_database_instance.this.name
}

resource "google_sql_user" "application" {
  project     = local.project
  name        = "oil_tracker"
  instance    = google_sql_database_instance.this.name
  password_wo = var.password
  # The provider requires a version alongside password_wo. This deployment
  # applies one initial password and recreates the database for password changes.
  password_wo_version = 1
}

resource "google_project_iam_member" "cloud_sql_client" {
  for_each = var.client_service_accounts

  project = local.project
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${each.value}"
}
