output "secret_resource_names" {
  description = "Fully qualified GCP Secret Manager resource names by secret ID."
  value = {
    for secret_id, secret in google_secret_manager_secret.this :
    secret_id => secret.name
  }
}

output "secret_ids" {
  description = "Secret IDs selected for GCP workloads."
  value       = local.all_secret_ids
}
