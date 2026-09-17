resource "google_compute_router" "main" {
  count   = length(local.vms) > 0 ? 1 : 0
  name    = "${local.resource_prefix}-router"
  network = google_compute_network.main[0].id
}

resource "google_compute_router_nat" "main" {
  count  = length(local.vms) > 0 ? 1 : 0
  name   = "${local.resource_prefix}-nat"
  router = google_compute_router.main[0].name

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.this["workload"].id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}
