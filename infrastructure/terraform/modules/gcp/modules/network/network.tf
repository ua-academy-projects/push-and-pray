resource "google_compute_network" "main" {
  name = "${var.resource_prefix}-vpc"

  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "management" {
  name          = "${var.resource_prefix}-management"
  network       = google_compute_network.main.id
  ip_cidr_range = var.profile.subnets.management
}

resource "google_compute_subnetwork" "workload" {
  name          = "${var.resource_prefix}-workload"
  network       = google_compute_network.main.id
  ip_cidr_range = var.profile.subnets.workload

  private_ip_google_access = true
}

resource "google_compute_subnetwork" "database" {
  count = var.enable_database_subnet ? 1 : 0

  name          = "${var.resource_prefix}-database"
  network       = google_compute_network.main.id
  ip_cidr_range = var.profile.subnets.database[0]

  private_ip_google_access = false
}
