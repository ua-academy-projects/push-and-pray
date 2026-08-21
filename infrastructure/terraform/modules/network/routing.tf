resource "google_compute_router" "main" {
  name    = "${var.resource_prefix}-router"
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "main" {
  name   = "${var.resource_prefix}-nat"
  router = google_compute_router.main.name

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.workload.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}