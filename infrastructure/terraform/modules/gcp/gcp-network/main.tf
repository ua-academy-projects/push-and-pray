resource "google_compute_network" "main" {
  count                   = length(local.vms) > 0 ? 1 : 0
  name                    = "${local.resource_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "this" {
  for_each = length(local.vms) > 0 ? {
    management = var.config.network.management_subnet_cidr
    workload   = var.config.network.workload_subnet_cidr
  } : {}

  name                     = "${local.resource_prefix}-${each.key}"
  network                  = google_compute_network.main[0].id
  ip_cidr_range            = each.value
  private_ip_google_access = each.key == "workload"
}
