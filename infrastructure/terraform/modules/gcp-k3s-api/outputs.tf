output "endpoint" {
  description = "Stable private K3s API endpoint, or null outside a GCP K3s deployment."
  value = local.enabled ? {
    host = google_compute_address.api[0].address
    port = var.config.k3s.api_server.port
  } : null
}
