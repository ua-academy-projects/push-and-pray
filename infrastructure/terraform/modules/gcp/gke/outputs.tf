output "summary" {
  description = "GKE connection, ingress, and registry integration values."
  value = {
    cluster_name         = google_container_cluster.this.name
    location             = google_container_cluster.this.location
    endpoint             = google_container_cluster.this.endpoint
    ingress_ip           = google_compute_global_address.ingress.address
    ingress_ip_name      = google_compute_global_address.ingress.name
    workload_pool        = "${var.project_id}.svc.id.goog"
    node_service_account = google_service_account.node.email
  }
}
