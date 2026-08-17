resource "google_compute_network" "main" {
  name                    = var.network_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "main" {
  name                     = var.subnet_name
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true
}

resource "google_compute_router" "main" {
  name    = var.router_name
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "main" {
  name                               = var.nat_name
  router                             = google_compute_router.main.name
  region                             = google_compute_router.main.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.main.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

resource "google_compute_address" "vm_internal" {
  for_each = var.internal_addresses

  name         = local.internal_address_names[each.key]
  address_type = "INTERNAL"
  address      = each.value
  region       = var.region
  subnetwork   = google_compute_subnetwork.main.id
}

resource "google_compute_address" "ui_external" {
  name         = "${local.name_prefix}-ui-external-ip"
  address_type = "EXTERNAL"
  region       = var.region
  network_tier = "PREMIUM"
}

resource "google_compute_firewall" "public_ui" {
  name    = "${local.name_prefix}-allow-public-ui"
  network = google_compute_network.main.name

  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.vm_network_tags.ui]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

resource "google_compute_firewall" "fetcher_to_infra" {
  name    = "${local.name_prefix}-allow-fetcher-infra"
  network = google_compute_network.main.name

  direction     = "INGRESS"
  source_ranges = ["${var.internal_addresses.fetcher}/32"]
  target_tags   = [local.vm_network_tags.infra]

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }
}

resource "google_compute_firewall" "history_to_infra" {
  name    = "${local.name_prefix}-allow-history-infra"
  network = google_compute_network.main.name

  direction     = "INGRESS"
  source_ranges = ["${var.internal_addresses.history}/32"]
  target_tags   = [local.vm_network_tags.infra]

  allow {
    protocol = "tcp"
    ports    = ["5432", "5672"]
  }
}

resource "google_compute_firewall" "ui_to_infra" {
  name    = "${local.name_prefix}-allow-ui-infra"
  network = google_compute_network.main.name

  direction     = "INGRESS"
  source_ranges = ["${var.internal_addresses.ui}/32"]
  target_tags   = [local.vm_network_tags.infra]

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }
}

resource "google_compute_firewall" "ui_to_history" {
  name    = "${local.name_prefix}-allow-ui-history"
  network = google_compute_network.main.name

  direction     = "INGRESS"
  source_ranges = ["${var.internal_addresses.ui}/32"]
  target_tags   = [local.vm_network_tags.history]

  allow {
    protocol = "tcp"
    ports    = ["8001"]
  }
}

