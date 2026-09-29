output "ip_address" {
  description = "Static public IPv4 address for K3s ingress, or null outside GCP K3s mode."
  value       = local.enabled ? google_compute_address.ingress[0].address : null
}

output "public_ips" {
  description = "Public ingress IP keyed for inclusion in the root public_ips output."
  value = local.enabled ? {
    ingress = google_compute_address.ingress[0].address
  } : {}
}
