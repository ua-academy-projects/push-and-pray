output "secret_ids" {
  description = "GCP secret container IDs created from the project configuration."
  value       = local.all_secret_ids
}

output "secret_resource_names" {
  description = "Fully qualified GCP secret resource names by secret ID."
  value = {
    for secret_id, secret in google_secret_manager_secret.this : secret_id => secret.name
  }
}
