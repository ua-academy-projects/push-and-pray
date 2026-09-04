locals {
  all_workload_vms = {
    for name, vm in local.config.vms : name => vm
    if vm.role != "bastion"
  }
}

output "bastion_public_ip" {
  description = "Bastion public IP, whichever cloud it was created on."
  value = coalesce(
    try(module.vm.public_ips["bastion"], null),
    try(module.aws_vm.public_ips["bastion"], null),
  )
}

output "workload_vm_names" {
  description = "VM names by workload, across both clouds."
  value = {
    for name in keys(local.all_workload_vms) :
    name => coalesce(try(module.vm.names[name], null), try(module.aws_vm.names[name], null))
  }
}

output "workload_roles" {
  description = "Roles by workload, across both clouds."
  value = {
    for name, workload in local.all_workload_vms : name => workload.role
  }
}

output "workload_internal_ips" {
  description = "Internal IPs by workload, across both clouds."
  value = {
    for name in keys(local.all_workload_vms) :
    name => coalesce(try(module.vm.internal_ips[name], null), try(module.aws_vm.internal_ips[name], null))
  }
}

output "workload_external_ips" {
  description = "External IPs by workload, across both clouds."
  value = {
    for name in keys(local.all_workload_vms) :
    name => coalesce(try(module.vm.public_ips[name], null), try(module.aws_vm.public_ips[name], null))
  }
}

output "workload_network_tags" {
  description = "Network tags by workload, across both clouds."
  value = {
    for name in keys(local.all_workload_vms) :
    name => coalesce(try(module.vm.network_tags[name], null), try(module.aws_vm.network_tags[name], null))
  }
}

output "workload_service_account_emails" {
  description = "GCP service-account emails by workload. GCP-only - AWS workloads have no equivalent here, see workload_iam_role_arns."
  value       = module.vm.service_account_emails
}

output "workload_iam_role_arns" {
  description = "AWS IAM role ARNs by workload. AWS-only - GCP workloads have no equivalent here, see workload_service_account_emails."
  value       = module.aws_vm.iam_role_arns
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
  description = "Secret IDs each workload service account may read, across both clouds. Names only - never values."
  value = {
    for name, workload in local.all_workload_vms :
    name => sort(distinct(values(workload.secret_mappings)))
  }
}
