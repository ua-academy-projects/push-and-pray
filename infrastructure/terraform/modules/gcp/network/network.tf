resource "google_compute_network" "main" {
  name = "${var.resource_prefix}-vpc"

  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "management" {
  name          = "${var.resource_prefix}-management"
  network       = google_compute_network.main.id
  ip_cidr_range = var.network_config.management_subnet_cidr
}

resource "google_compute_subnetwork" "workload" {
  name          = "${var.resource_prefix}-workload"
  network       = google_compute_network.main.id
  ip_cidr_range = var.network_config.workload_subnet_cidr

  private_ip_google_access = true
}
