output "identity" {
  description = "Email of the service account. The GCP equivalent of the AWS module's role ARN."
  value       = google_service_account.workload.email
}

output "member" {
  description = "The service account as an IAM member string, ready to use in a binding."
  value       = "serviceAccount:${google_service_account.workload.email}"
}

output "email" {
  description = "Email of the service account."
  value       = google_service_account.workload.email
}

output "name" {
  description = "Fully qualified resource name of the service account."
  value       = google_service_account.workload.name
}

output "id" {
  description = "Resource ID of the service account."
  value       = google_service_account.workload.id
}

output "unique_id" {
  description = "Numeric unique ID, which survives a rename."
  value       = google_service_account.workload.unique_id
}

output "account_id" {
  description = "Short account ID, the part before the @ in the email."
  value       = google_service_account.workload.account_id
}
