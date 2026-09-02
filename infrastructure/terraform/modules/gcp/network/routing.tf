resource "google_compute_router" "main" {
  for_each = local.instances

  name    = "${local.resource_prefix}-router"
  network = google_compute_network.main[each.key].id
  region  = local.region
}

resource "google_compute_router_nat" "main" {
  for_each = local.instances

  name   = "${local.resource_prefix}-nat"
  router = google_compute_router.main[each.key].name
  region = local.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.workload[each.key].id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}
