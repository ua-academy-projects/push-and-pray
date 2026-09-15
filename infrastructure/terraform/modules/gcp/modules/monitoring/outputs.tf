output "metrics" {
  description = "The watched metrics - title, filter, aligner and threshold - for alerting to build one policy per entry."
  value       = local.metrics
}

output "dashboard_id" {
  description = "Resource name of the dashboard."
  value       = google_monitoring_dashboard.hosts.id
}
