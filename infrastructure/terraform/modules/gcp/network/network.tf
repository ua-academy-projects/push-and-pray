resource "google_compute_network" "main" {
  name = "${var.resource_prefix}-vpc"

  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "management" {
  name          = "${var.resource_prefix}-management"
  network       = google_compute_network.main.id
  ip_cidr_range = var.management_subnet_cidr
  region        = var.region
}

resource "google_compute_subnetwork" "workload" {
  name          = "${var.resource_prefix}-workload"
  network       = google_compute_network.main.id
  ip_cidr_range = var.workload_subnet_cidr
  region        = var.region

  private_ip_google_access = true
}
