# create vpc

resource "google_compute_network" "vpc" {
  project     = var.project_id
  name        = "${local.prefix}-vpc"
  description = "Custom-mode VPC for ${local.prefix}: public bastion subnet + private workload subnet."

  auto_create_subnetworks = false
  routing_mode            = var.routing_mode
  mtu                     = var.mtu

  # See routing.tf: when true the implicit default route is dropped and replaced
  # by an explicitly managed one.
  delete_default_routes_on_create = var.manage_default_route
}

# create subnets

resource "google_compute_subnetwork" "public" {
  project     = var.project_id
  name        = "${local.prefix}-subnet-public"
  description = "Public subnet: bastion host only."

  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.public_subnet_cidr

  # Not needed here (the bastion has a public IP and a route to the internet),
  # but harmless and keeps behaviour identical if the external IP is ever removed.
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "private" {
  project     = var.project_id
  name        = "${local.prefix}-subnet-private"
  description = "Private subnet: application and database instances, no external IPs."

  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.private_subnet_cidr

  # Lets instances without an external IP reach Google APIs (Artifact Registry,
  # Cloud Logging, Secret Manager, ...) over internal IPs instead of via NAT.
  private_ip_google_access = true

  dynamic "secondary_ip_range" {
    for_each = var.private_secondary_ranges

    content {
      range_name    = secondary_ip_range.key
      ip_cidr_range = secondary_ip_range.value
    }
  }
}