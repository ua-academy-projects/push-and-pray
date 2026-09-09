output "bastion_public_ips" {
  description = "Public IP of this cloud's bastion, keyed by cloud name. Empty when the cloud is inactive."
  value = {
    for instance in module.bastion : local.this_cloud => instance.public_ip
  }
}

output "workload_vm_names" {
  description = "VM names by workload."
  value = {
    for name, workload in local.workload_vms : name => module.vm[name].name
  }
}

output "workload_roles" {
  description = "Roles by workload."
  value = {
    for name, workload in local.workload_vms : name => workload.role
  }
}

output "workload_clouds" {
  description = "Cloud hosting each workload. Matches the cloud label the Ansible inventory selects on."
  value = {
    for name, workload in local.workload_vms : name => local.this_cloud
  }
}

output "workload_internal_ips" {
  description = "Internal IPs by workload."
  value = {
    for name, workload in local.workload_vms : name => module.vm[name].internal_ip
  }
}

output "workload_external_ips" {
  description = "External IPs by workload."
  value = {
    for name, workload in local.workload_vms : name => module.vm[name].public_ip
  }
}

output "workload_network_scopes" {
  description = "Network tags each workload carries."
  value = {
    for name, workload in local.workload_vms : name => module.vm[name].network_tags
  }
}

output "workload_identities" {
  description = "Service-account email of each workload."
  value = {
    for name, workload in local.workload_vms : name => module.identity[name].identity
  }
}

output "secret_ids" {
  description = "Secret Manager container IDs created from the project configuration."
  value       = sort(local.all_secret_ids)
}

output "secret_resource_names" {
  description = "Fully qualified Secret Manager resource names, by secret ID."
  value = {
    for secret_id, secret in google_secret_manager_secret.this : secret_id => secret.name
  }
}

output "workload_secret_access" {
  description = "Secret IDs each workload service account may read. Names only - never values."
  value = {
    for name, workload in local.workload_vms :
    name => sort(distinct(values(workload.secret_mappings)))
  }
}
