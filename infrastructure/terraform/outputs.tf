output "clouds" {
  description = "Clouds this state has resources in."
  value       = sort(local.clouds)
}

output "workload_clouds" {
  description = "Cloud each VM was created in."
  value = {
    for name, vm in local.vms : name => vm.cloud
  }
}

output "regions" {
  description = "Provider region per cloud in use, resolved from the portable location token."
  value = {
    for cloud in local.clouds : cloud => local.region[cloud]
  }
}

output "bastion_public_ip" {
  description = "Bastion public IP."
  value       = local.vm["bastion"].public_ip
}

output "workload_vm_names" {
  description = "VM names by workload."
  value = {
    for name, workload in local.workload_vms : name => local.vm[name].name
  }
}

output "workload_roles" {
  description = "Roles by workload."
  value = {
    for name, workload in local.workload_vms : name => workload.role
  }
}

output "workload_internal_ips" {
  description = "Internal IPs by workload."
  value = {
    for name, workload in local.workload_vms : name => local.vm[name].internal_ip
  }
}

output "workload_external_ips" {
  description = "External IPs by workload."
  value = {
    for name, workload in local.workload_vms : name => local.vm[name].public_ip
  }
}

output "workload_network_groups" {
  description = "Network group identifiers by workload. Compute Engine network tags on GCP; security group IDs on AWS."
  value = {
    for name, workload in local.workload_vms : name => local.vm[name].network_groups
  }
}

output "workload_runtime_identities" {
  description = "Identity each workload runs as. Service-account emails on GCP; IAM role names on AWS."
  value = {
    for name, workload in local.workload_vms : name => local.vm[name].runtime_identity
  }
}

output "secret_ids" {
  description = "Secret container IDs created from the project configuration."
  value       = sort(local.all_secret_ids)
}

output "secret_resource_names" {
  description = "Fully qualified secret resource names, by secret ID. Never values."
  value = merge(
    { for secret_id, secret in google_secret_manager_secret.this : secret_id => secret.name },
    { for secret_id, secret in aws_secretsmanager_secret.this : secret_id => secret.arn },
  )
}

output "workload_secret_access" {
  description = "Secret IDs each workload runtime identity may read. Names only - never values."
  value = {
    for name, workload in local.workload_vms :
    name => sort(distinct(values(workload.secret_mappings)))
  }
}
