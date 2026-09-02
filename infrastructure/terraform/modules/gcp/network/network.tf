resource "google_compute_network" "main" {
  for_each = local.instances

  name = "${local.resource_prefix}-vpc"

  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  lifecycle {
    precondition {
      condition     = contains(var.project_services, "compute.googleapis.com")
      error_message = "The Compute Engine API must be enabled before creating the GCP network."
    }
  }
}

resource "google_compute_subnetwork" "management" {
  for_each = local.instances

  name          = "${local.resource_prefix}-management"
  network       = google_compute_network.main[each.key].id
  ip_cidr_range = var.config.network.management_subnet_cidr
  region        = local.region
}

resource "google_compute_subnetwork" "workload" {
  for_each = local.instances

  name          = "${local.resource_prefix}-workload"
  network       = google_compute_network.main[each.key].id
  ip_cidr_range = var.config.network.workload_subnet_cidr
  region        = local.region

  private_ip_google_access = true
}
