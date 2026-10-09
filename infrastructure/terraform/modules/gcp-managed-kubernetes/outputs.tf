output "cluster" {
  description = "GKE cluster connection metadata."
  value = {
    name         = google_container_cluster.this.name
    location     = google_container_cluster.this.location
    endpoint     = google_container_cluster.this.endpoint
    worker_zones = local.worker_zones
  }
}

output "ingress" {
  description = "Reserved public address for the managed ingress controller."
  value = {
    address         = google_compute_address.ingress.address
    name            = google_compute_address.ingress.name
    private_address = google_compute_address.private_ingress.address
    private_name    = google_compute_address.private_ingress.name
  }
}
