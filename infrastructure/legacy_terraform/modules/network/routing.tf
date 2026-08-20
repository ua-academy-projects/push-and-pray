resource "google_compute_route" "default_internet" {
  count = var.manage_default_route ? 1 : 0

  project     = var.project_id
  name        = "${local.prefix}-rt-default-internet"
  description = "Explicitly managed default route. Replaces the auto-created one so routing is visible in the plan."

  network          = google_compute_network.vpc.id
  dest_range       = "0.0.0.0/0"
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
}

# Cloud NAT for workload subnet

resource "google_compute_router" "router" {
  count = var.enable_nat ? 1 : 0

  project     = var.project_id
  name        = "${local.prefix}-router"
  description = "Cloud Router hosting the NAT gateway for the workload subnet."
  region      = var.region
  network     = google_compute_network.vpc.id
}

resource "google_compute_address" "nat" {
  count = var.enable_nat ? var.nat_static_ip_count : 0

  project      = var.project_id
  name         = "${local.prefix}-nat-ip-${count.index + 1}"
  description  = "Static egress IP for Cloud NAT - hand this to partners that require IP allow-listing."
  region       = var.region
  address_type = "EXTERNAL"
  labels       = local.labels
}

resource "google_compute_router_nat" "nat" {
  count = var.enable_nat ? 1 : 0

  project = var.project_id
  name    = "${local.prefix}-nat"
  router  = google_compute_router.router[0].name
  region  = var.region

  nat_ip_allocate_option = var.nat_static_ip_count > 0 ? "MANUAL_ONLY" : "AUTO_ONLY"
  nat_ips                = var.nat_static_ip_count > 0 ? google_compute_address.nat[*].self_link : null

  # Only the workload subnet is NATed. The bastion uses its own external IP,
  # so it never consumes NAT ports.
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = var.nat_log_filter
  }
}
