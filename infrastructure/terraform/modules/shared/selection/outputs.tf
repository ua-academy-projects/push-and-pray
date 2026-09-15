output "profile" {
  description = "This cloud's profile from the configuration, or null when it declares none."
  value       = local.profile
}

output "is_active" {
  description = "Whether this cloud hosts any workload. False means the caller builds nothing at all."
  value       = local.is_active
}

output "workload_vms" {
  description = "Workloads the calling module manages. Empty unless the cloud is active."
  value       = local.workload_vms
}

output "resource_prefix" {
  description = "Prefix shared by every resource name."
  value       = "${var.config.name_prefix}-${var.config.environment}"
}

output "common_labels" {
  description = "Labels or tags applied to every resource, including the cloud key the Ansible inventory selects on."
  value       = local.common_labels
}

output "cloud" {
  description = "The cloud this instance of the module answered for."
  value       = var.cloud
}

output "cloud_vms" {
  description = "Every workload the configuration assigns to this cloud, whether or not it is built. Compare with workload_vms to see what the active check dropped."
  value       = local.cloud_vms
}

output "skipped_vms" {
  description = "Workloads assigned to this cloud that are deliberately not built. Empty whenever the cloud is active."
  value = {
    for name, vm in local.cloud_vms : name => vm
    if !local.is_active
  }
}

output "database_managed" {
  description = "Whether the project runs PostgreSQL as a managed service. The same answer on every cloud; see builds_database for who acts on it."
  value       = local.database_managed
}

output "builds_database" {
  description = "Whether this cloud creates the managed database: it is active, the database is managed, and the infra VM is here."
  value       = local.builds_database
}

output "database_size" {
  description = "This provider's tier for the configured database size label, or null when the label is not in its database_sizes."
  value       = local.database_size
}

output "database_settings" {
  description = "The database block of the configuration, as written."
  value       = var.config.database
}
