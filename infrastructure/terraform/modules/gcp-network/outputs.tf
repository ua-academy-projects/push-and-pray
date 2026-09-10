output "networks" {
  description = "GCP network identifiers keyed by logical location."
  value = {
    for location in keys(local.placements) : location => {
      network_id        = google_compute_network.this[location].id
      public_subnet_id  = google_compute_subnetwork.public[location].id
      private_subnet_id = google_compute_subnetwork.private[location].id
    }
  }
}
