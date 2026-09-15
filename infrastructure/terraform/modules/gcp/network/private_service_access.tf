resource "google_compute_global_address" "private_services" {
    count = var.has_selected_vms && try(var.config.managed_db.enabled, false) ? 1 : 0

    name = "${local.resource_prefix}-cloudsql-psa"
    purpose = "VPC_PEERING"
    address_type = "INTERNAL"
    prefix_length = 24
    network = google_compute_network.main[0].id
}

resource "google_service_networking_connection" "private_services" {
    count = var.has_selected_vms && try(var.config.managed_db.enabled, false) ? 1 : 0

    network = google_compute_network.main[0].id
    service = "servicenetworking.googleapis.com"
    reserved_peering_ranges = [google_compute_global_address.private_services[0].name]
}

