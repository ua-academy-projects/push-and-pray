output "bastion_public_ip" {
  description = "Bastion public IP, independent of its cloud."
  value       = lookup(merge(module.gcp.public_ips, module.aws.public_ips), "bastion", null)
}

output "workload_vm_names" {
  description = "VM names by workload across all configured clouds."
  value       = merge(module.gcp.workload_names, module.aws.workload_names)
}

output "workload_roles" {
  description = "Roles by workload across all configured clouds."
  value       = merge(module.gcp.workload_roles, module.aws.workload_roles)
}

output "workload_internal_ips" {
  description = "Internal IPs by workload across all configured clouds."
  value       = merge(module.gcp.workload_private_ips, module.aws.workload_private_ips)
}

output "workload_external_ips" {
  description = "External IPs by workload across all configured clouds."
  value       = merge(module.gcp.workload_public_ips, module.aws.workload_public_ips)
}

output "workload_network_tags" {
  description = "GCP network tags by workload."
  value       = module.gcp.workload_network_tags
}

output "workload_service_account_emails" {
  description = "GCP service-account emails by workload."
  value       = module.gcp.workload_service_account_emails
}

output "secret_ids" {
  description = "GCP Secret Manager container IDs created from the project configuration."
  value       = module.gcp.secret_ids
}

output "secret_resource_names" {
  description = "Fully qualified GCP Secret Manager resource names by secret ID."
  value       = module.gcp.secret_resource_names
}

output "workload_secret_access" {
  description = "Secret IDs each GCP workload service account may read."
  value       = module.gcp.workload_secret_access
}
