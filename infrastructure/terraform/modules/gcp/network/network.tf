resource "google_compute_network" "main" {
  count = var.has_selected_vms ? 1 : 0
  name = "${local.resource_prefix}-vpc"

  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "management" {
  count = var.has_selected_vms ? 1 : 0
  name          = "${local.resource_prefix}-management"
  network       = google_compute_network.main[0].id
  ip_cidr_range = var.config.network.management_subnet_cidr
}

resource "google_compute_subnetwork" "workload" {
  count = var.has_selected_vms ? 1 : 0
  name          = "${local.resource_prefix}-workload"
  network       = google_compute_network.main[0].id
  ip_cidr_range = var.config.network.workload_subnet_cidr

  private_ip_google_access = true
}