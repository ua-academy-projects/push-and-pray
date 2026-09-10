resource "google_compute_network" "this" {
  for_each = local.placements

  name                    = "${local.context.resource_prefix}-${each.key}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "public" {
  for_each = local.placements

  name          = "${local.context.resource_prefix}-${each.key}-public"
  region        = each.value.region
  network       = google_compute_network.this[each.key].id
  ip_cidr_range = var.config.network.public_subnet_cidr
}

resource "google_compute_subnetwork" "private" {
  for_each = local.placements

  name                     = "${local.context.resource_prefix}-${each.key}-private"
  region                   = each.value.region
  network                  = google_compute_network.this[each.key].id
  ip_cidr_range            = var.config.network.private_subnet_cidr
  private_ip_google_access = true
}

resource "google_compute_router" "this" {
  for_each = local.placements

  name    = "${local.context.resource_prefix}-${each.key}-router"
  region  = each.value.region
  network = google_compute_network.this[each.key].id
}

resource "google_compute_router_nat" "this" {
  for_each = local.placements

  name                               = "${local.context.resource_prefix}-${each.key}-nat"
  region                             = each.value.region
  router                             = google_compute_router.this[each.key].name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private[each.key].id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}
