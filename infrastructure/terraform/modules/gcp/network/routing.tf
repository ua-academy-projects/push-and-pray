resource "google_compute_router" "main" {
  for_each = local.locations

  name    = "${local.resource_prefix}-router${local.location_suffixes[each.key]}"
  network = google_compute_network.main[each.key].id
  region  = each.value.region
}

resource "google_compute_router_nat" "main" {
  for_each = local.locations

  name   = "${local.resource_prefix}-nat${local.location_suffixes[each.key]}"
  router = google_compute_router.main[each.key].name
  region = each.value.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.workload[each.key].id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}
