resource "google_compute_network" "main" {
  name = "${var.config.name_prefix}-${var.config.environment}-vpc"

  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "management" {
  name          = "${var.config.name_prefix}-${var.config.environment}-management"
  network       = google_compute_network.main.id
  ip_cidr_range = var.config.network.management_subnet_cidr
}

resource "google_compute_subnetwork" "vm" {
  name          = "${var.config.name_prefix}-${var.config.environment}-vm"
  network       = google_compute_network.main.id
  ip_cidr_range = var.config.network.workload_subnet_cidr

  private_ip_google_access = true
}

resource "google_compute_global_address" "private_services" {
  name          = "${var.config.name_prefix}-${var.config.environment}-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = cidrhost(var.config.network.database_connectivity.gcp.private_service_cidr, 0)
  prefix_length = tonumber(split("/", var.config.network.database_connectivity.gcp.private_service_cidr)[1])
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_services" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}
