locals {
  vm_names = merge(
    { for name, vm in module.gcp_vm.vms : name => vm.name },
    { for name, vm in module.aws_vm.vms : name => vm.name },
  )

  vm_internal_ips = merge(
    { for name, vm in module.gcp_vm.vms : name => vm.internal_ip },
    { for name, vm in module.aws_vm.vms : name => vm.internal_ip },
  )

  vm_public_ips = merge(
    { for name, vm in module.gcp_vm.vms : name => vm.public_ip },
    { for name, vm in module.aws_vm.vms : name => vm.public_ip },
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
    for name, vm in module.gcp_vm.vms : name => vm.network_tags
    if contains(keys(local.workload_vms), name)
  }
}

output "workload_service_account_emails" {
  description = "GCP service-account emails by GCP workload."
  value = {
    for name, vm in module.gcp_vm.vms : name => vm.service_account_email
    if contains(keys(local.workload_vms), name)
  }
}

output "secret_ids" {
  description = "Secret container IDs created from the project configuration across all clouds."
  value = sort(distinct(concat(
    module.gcp_secrets.secret_ids,
    module.aws_secrets.secret_ids,
  )))
}

output "secret_resource_names" {
  description = "Fully qualified secret resource names by cloud and secret ID."
  value = {
    gcp = module.gcp_secrets.secret_resource_names
    aws = module.aws_secrets.secret_resource_names
  }
}

output "workload_secret_access" {
  description = "Secret IDs each workload identity may read. Names only - never values."
  value = {
    for name, workload in local.workload_vms :
    name => sort(distinct(values(workload.secret_mappings)))
  }
}
