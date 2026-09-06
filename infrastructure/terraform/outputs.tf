locals {
  vm_names = merge(
    { for name, vm in module.gcp_vm : name => vm.name },
    { for name, vm in module.aws_vms : name => vm.name },
  )

  vm_internal_ips = merge(
    { for name, vm in module.gcp_vm : name => vm.internal_ip },
    { for name, vm in module.aws_vms : name => vm.internal_ip },
  )

  vm_public_ips = merge(
    { for name, vm in module.gcp_vm : name => vm.public_ip },
    { for name, vm in module.aws_vms : name => vm.public_ip },
  )
}

output "bastion_public_ip" {
  description = "Bastion public IP."
  value       = local.vm_public_ips["bastion"]
}

output "workload_vm_names" {
  description = "VM names by workload."
  value = {
    for name, workload in local.workload_vms : name => local.vm_names[name]
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
    for name, workload in local.workload_vms : name => local.vm_internal_ips[name]
  }
}

output "workload_external_ips" {
  description = "External IPs by workload."
  value = {
    for name, workload in local.workload_vms : name => local.vm_public_ips[name]
  }
}

output "workload_network_tags" {
  description = "GCP network tags by GCP workload."
  value = {
    for name, workload in local.gcp_vms : name => module.gcp_vm[name].network_tags
    if workload.role != "bastion"
  }
}

output "workload_service_account_emails" {
  description = "GCP service-account emails by GCP workload."
  value = {
    for name, workload in local.gcp_vms : name => module.gcp_vm[name].service_account_email
    if workload.role != "bastion"
  }
}

output "secret_ids" {
  description = "Secret container IDs created from the project configuration across all clouds."
  value = sort(distinct(concat(
    local.all_secret_ids,
    local.aws_all_secret_ids,
  )))
}

output "secret_resource_names" {
  description = "Fully qualified secret resource names by cloud and secret ID."
  value = {
    gcp = {
      for secret_id, secret in google_secret_manager_secret.this : secret_id => secret.name
    }
    aws = {
      for secret_id, secret in aws_secretsmanager_secret.this : secret_id => secret.arn
    }
  }
}

output "workload_secret_access" {
  description = "Secret IDs each workload identity may read. Names only - never values."
  value = {
    for name, workload in local.workload_vms :
    name => sort(distinct(values(workload.secret_mappings)))
  }
}
