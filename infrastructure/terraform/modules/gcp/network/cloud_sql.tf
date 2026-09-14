resource "google_project_service" "service_networking" {
  count              = local.cloud_sql_enabled ? 1 : 0
  project            = var.config.clouds.gcp.project_id
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_compute_global_address" "cloud_sql" {
  count         = local.cloud_sql_enabled ? 1 : 0
  name          = "${local.resource_prefix}-cloud-sql"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = cidrhost(var.config.clouds.gcp.cloud_sql_network.allocated_cidr, 0)
  prefix_length = tonumber(split("/", var.config.clouds.gcp.cloud_sql_network.allocated_cidr)[1])
  network       = google_compute_network.main[0].id
}

resource "google_service_networking_connection" "cloud_sql" {
  count                   = local.cloud_sql_enabled ? 1 : 0
  network                 = google_compute_network.main[0].id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.cloud_sql[0].name]
  depends_on              = [google_project_service.service_networking]
}

# Cloud SQL lives in Google's VPC and cannot use workload ingress tags.
# Restrict traffic at the source VMs instead, overriding implied allow-egress.
resource "google_compute_firewall" "cloud_sql_clients" {
  count              = local.cloud_sql_enabled ? 1 : 0
  name               = "${local.resource_prefix}-cloud-sql-clients"
  network            = google_compute_network.main[0].id
  direction          = "EGRESS"
  priority           = 900
  destination_ranges = [var.config.clouds.gcp.cloud_sql_network.allocated_cidr]
  target_tags        = [local.network_tags.fetcher, local.network_tags.history]
  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }
}

resource "google_compute_firewall" "cloud_sql_deny" {
  count              = local.cloud_sql_enabled ? 1 : 0
  name               = "${local.resource_prefix}-cloud-sql-deny"
  network            = google_compute_network.main[0].id
  direction          = "EGRESS"
  priority           = 1000
  destination_ranges = [var.config.clouds.gcp.cloud_sql_network.allocated_cidr]
  deny {
    protocol = "all"
  }
}
