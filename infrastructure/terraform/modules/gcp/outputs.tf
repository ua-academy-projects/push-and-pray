output "names" {
  description = "GCP VM names by configuration key."
  value       = local.has_vms ? module.vm[0].names : {}
}

output "private_ips" {
  description = "GCP VM private IPs by configuration key."
  value       = local.has_vms ? module.vm[0].private_ips : {}
}

output "public_ips" {
  description = "GCP VM public IPs by configuration key."
  value       = local.has_vms ? module.vm[0].public_ips : {}
}

output "roles" {
  description = "GCP VM roles by configuration key."
  value = {
    for name, vm in local.resolved_vms : name => vm.role
  }
}

output "workload_names" {
  description = "GCP workload VM names, excluding the bastion."
  value = local.has_vms ? {
    for name, vm in local.workload_vms : name => module.vm[0].names[name]
  } : {}
}

output "workload_roles" {
  description = "GCP workload roles, excluding the bastion."
  value = {
    for name, vm in local.workload_vms : name => vm.role
  }
}

output "workload_private_ips" {
  description = "GCP workload private IPs, excluding the bastion."
  value = local.has_vms ? {
    for name, vm in local.workload_vms : name => module.vm[0].private_ips[name]
  } : {}
}

output "workload_public_ips" {
  description = "GCP workload public IPs, excluding the bastion."
  value = local.has_vms ? {
    for name, vm in local.workload_vms : name => module.vm[0].public_ips[name]
  } : {}
}

output "workload_network_tags" {
  description = "GCP network tags by workload."
  value = local.has_vms ? {
    for name, vm in local.workload_vms : name => module.vm[0].network_tags[name]
  } : {}
}

output "workload_service_account_emails" {
  description = "GCP service-account emails by workload."
  value = local.has_vms ? {
    for name, vm in local.workload_vms : name => module.vm[0].service_account_emails[name]
  } : {}
}

output "secret_ids" {
  description = "GCP Secret Manager container IDs."
  value       = module.secrets.secret_ids
}

output "secret_resource_names" {
  description = "Fully qualified GCP Secret Manager resource names by secret ID."
  value       = module.secrets.secret_resource_names
}

output "workload_secret_access" {
  description = "Secret IDs each GCP workload service account may read."
  value       = module.secrets.workload_secret_access
}

output "monitoring" {
  description = "GCP observability resource identifiers, or null when monitoring is disabled."
  value       = local.monitoring_enabled ? module.monitoring[0].summary : null
}
