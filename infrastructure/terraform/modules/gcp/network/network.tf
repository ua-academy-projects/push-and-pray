resource "google_compute_network" "main" {
  for_each = local.locations

  name = "${local.resource_prefix}-vpc${local.location_suffixes[each.key]}"

  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "management" {
  for_each = local.locations

  name          = "${local.resource_prefix}-management${local.location_suffixes[each.key]}"
  network       = google_compute_network.main[each.key].id
  ip_cidr_range = var.config.network.management_subnet_cidr
  region        = each.value.region
}

resource "google_compute_subnetwork" "workload" {
  for_each = local.locations

  name          = "${local.resource_prefix}-workload${local.location_suffixes[each.key]}"
  network       = google_compute_network.main[each.key].id
  ip_cidr_range = var.config.network.workload_subnet_cidr
  region        = each.value.region

  private_ip_google_access = true
}
