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