output "networks" {
  description = "GCP network identifiers keyed by logical location."
  value = {
    for location in keys(local.placements) : location => {
      network_id           = google_compute_network.this[location].id
      management_subnet_id = google_compute_subnetwork.management[location].id
      workload_subnet_id   = google_compute_subnetwork.workload[location].id
    }
  }
}
