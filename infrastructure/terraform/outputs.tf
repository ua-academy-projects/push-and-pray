output "bastion_public_ips" {
  description = "Public IP of every bastion, by VM name. Each cloud runs its own."
  value       = merge(module.gcp.bastion_public_ips, module.aws.bastion_public_ips)
}

output "workload_vm_names" {
  description = "VM names by workload."
  value       = merge(module.gcp.workload_vm_names, module.aws.workload_vm_names)
}

output "workload_roles" {
  description = "Roles by workload."
  value       = merge(module.gcp.workload_roles, module.aws.workload_roles)
}

output "workload_clouds" {
  description = "Cloud hosting each workload. Matches the cloud label the Ansible inventory selects on."
  value       = merge(module.gcp.workload_clouds, module.aws.workload_clouds)
}

output "workload_internal_ips" {
  description = "Internal IPs by workload."
  value       = merge(module.gcp.workload_internal_ips, module.aws.workload_internal_ips)
}

output "workload_external_ips" {
  description = "External IPs by workload."
  value       = merge(module.gcp.workload_external_ips, module.aws.workload_external_ips)
}

output "workload_network_scopes" {
  description = "Firewall scopes each workload belongs to: network tags on GCP, security group IDs on AWS."
  value       = merge(module.gcp.workload_network_scopes, module.aws.workload_network_scopes)
}

output "workload_identities" {
  description = "Runtime identity of each workload: a service-account email on GCP, an IAM role ARN on AWS."
  value       = merge(module.gcp.workload_identities, module.aws.workload_identities)
}

output "secret_ids" {
  description = "Secret container IDs created from the project configuration."
  value       = sort(distinct(concat(module.gcp.secret_ids, module.aws.secret_ids)))
}

output "secret_resource_names" {
  description = "Fully qualified secret resource names, by secret ID."
  value       = merge(module.gcp.secret_resource_names, module.aws.secret_resource_names)
}

output "workload_secret_access" {
  description = "Secret IDs each workload identity may read. Names only - never values."
  value       = merge(module.gcp.workload_secret_access, module.aws.workload_secret_access)
}

output "database" {
  description = "The managed database, from whichever cloud builds it: mode, cloud, host, port, name, username, instance, and on AWS the ARN of the RDS-managed password secret. Null in self-hosted mode - the database is then the infra VM's PostgreSQL container, at workload_internal_ips.infra."
  value       = module.gcp.database != null ? module.gcp.database : module.aws.database
}
