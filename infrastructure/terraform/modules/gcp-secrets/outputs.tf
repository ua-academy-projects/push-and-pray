output "secret_ids" {
  description = "GCP Secret Manager secret IDs created for GCP workloads."
  value       = sort(local.all_secret_ids)
}

output "secret_resource_names" {
  description = "GCP Secret Manager resource names keyed by secret ID."
  value = {
    for secret_id, secret in google_secret_manager_secret.this : secret_id => secret.name
  }
}

output "workload_secret_access" {
  description = "Secret IDs available to each GCP workload."
  value = {
    for name, workload in local.workload_vms :
    name => sort(distinct(values(workload.secret_mappings)))
  }
}
