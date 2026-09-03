output "names" {
  description = "GCP VM names by configuration key."
  value = {
    for name, instance in module.vm : name => instance.name
  }
}

output "private_ips" {
  description = "GCP VM private IPs by configuration key."
  value = {
    for name, instance in module.vm : name => instance.internal_ip
  }
}

output "public_ips" {
  description = "GCP VM public IPs by configuration key."
  value = {
    for name, instance in module.vm : name => instance.public_ip
  }
}

output "roles" {
  description = "GCP VM roles by configuration key."
  value = {
    for name, vm in local.resolved_vms : name => vm.role
  }
}

output "workload_names" {
  description = "GCP workload VM names, excluding the bastion."
  value = {
    for name, vm in local.workload_vms : name => module.vm[name].name
  }
}

output "workload_roles" {
  description = "GCP workload roles, excluding the bastion."
  value = {
    for name, vm in local.workload_vms : name => vm.role
  }
}

output "workload_private_ips" {
  description = "GCP workload private IPs, excluding the bastion."
  value = {
    for name, vm in local.workload_vms : name => module.vm[name].internal_ip
  }
}

output "workload_public_ips" {
  description = "GCP workload public IPs, excluding the bastion."
  value = {
    for name, vm in local.workload_vms : name => module.vm[name].public_ip
  }
}

output "workload_network_tags" {
  description = "GCP network tags by workload."
  value = {
    for name, vm in local.workload_vms : name => module.vm[name].network_tags
  }
}

output "workload_service_account_emails" {
  description = "GCP service-account emails by workload."
  value = {
    for name, vm in local.workload_vms : name => module.vm[name].service_account_email
  }
}

output "secret_ids" {
  description = "GCP Secret Manager container IDs."
  value       = sort(local.all_secret_ids)
}

output "secret_resource_names" {
  description = "Fully qualified GCP Secret Manager resource names by secret ID."
  value = {
    for secret_id, secret in google_secret_manager_secret.this : secret_id => secret.name
  }
}

output "workload_secret_access" {
  description = "Secret IDs each GCP workload service account may read."
  value = {
    for name, workload in local.workload_vms :
    name => sort(distinct(values(workload.secret_mappings)))
  }
}
