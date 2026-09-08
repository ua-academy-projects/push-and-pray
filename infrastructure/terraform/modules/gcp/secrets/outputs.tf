output "secret_ids" {
  description = "Logical Secret Manager IDs created by this module."
  value       = sort(tolist(var.secret_ids))
}

output "secret_resource_names" {
  description = "Fully qualified Secret Manager resource names by logical ID."
  value = {
    for secret_id, secret in google_secret_manager_secret.this :
    secret_id => secret.name
  }
}

output "workload_secret_access" {
  description = "Logical secret IDs each workload service account may read."
  value = {
    for name, secret_ids in var.secret_ids_by_vm :
    name => sort(secret_ids)
  }
}
