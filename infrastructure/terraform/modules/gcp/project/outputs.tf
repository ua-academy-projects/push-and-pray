output "services" {
  description = "Enabled GCP project services."
  value       = keys(google_project_service.required)
}
