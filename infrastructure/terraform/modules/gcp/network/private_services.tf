resource "google_compute_global_address" "database_private_service_range" {
  count = local.managed_database_enabled ? 1 : 0

  name          = "${local.resource_prefix}-database-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.config.network.database_private_service_prefix_length
  network       = google_compute_network.main[var.config.default_location].id
}

resource "google_service_networking_connection" "database" {
  count = local.managed_database_enabled ? 1 : 0

  network                 = google_compute_network.main[var.config.default_location].id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.database_private_service_range[0].name]
}
