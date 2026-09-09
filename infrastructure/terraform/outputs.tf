locals {
  all_workload_vms = {
    for name, vm in local.config.vms : name => vm
    if vm.role != "bastion"
  }
}

output "bastion_public_ip" {
  value = try(coalesce(
    try(module.gcp_vm.public_ips["bastion"], null),
    try(module.aws_vm.public_ips["bastion"], null),
  ), null)
}

output "workload_vm_names" {
  value = {
    for name in keys(local.all_workload_vms) :
    name => coalesce(try(module.gcp_vm.names[name], null), try(module.aws_vm.names[name], null))
  }
}

output "workload_roles" {
  value = {
    for name, workload in local.all_workload_vms : name => workload.role
  }
}

output "workload_internal_ips" {
  value = {
    for name in keys(local.all_workload_vms) :
    name => coalesce(try(module.gcp_vm.internal_ips[name], null), try(module.aws_vm.internal_ips[name], null))
  }
}

output "workload_external_ips" {
  value = {
    for name in keys(local.all_workload_vms) :
    name => try(coalesce(try(module.gcp_vm.public_ips[name], null), try(module.aws_vm.public_ips[name], null)), null)
  }
}

output "workload_network_tags" {
  value = {
    for name in keys(local.all_workload_vms) :
    name => coalesce(try(module.gcp_vm.network_tags[name], null), try(module.aws_vm.network_tags[name], null))
  }
}

output "workload_service_account_emails" {
  value       = module.gcp_vm.service_account_emails
}

output "workload_iam_role_arns" {
  value       = module.aws_vm.iam_role_arns
}

output "secret_ids" {
  description = "Secret Manager container IDs created from the project configuration."
  value       = module.gcp_vm.secret_ids
}

output "secret_resource_names" {
  description = "Fully qualified Secret Manager resource names, by secret ID."
  value       = module.gcp_vm.secret_resource_names
}

output "workload_secret_access" {
  value = {
    for name, workload in local.all_workload_vms :
    name => sort(distinct(values(workload.secret_mappings)))
  }
}
