locals {
  vm_outputs_by_name = merge(module.gcp_vm.vms, module.aws_vm.vms)
  workload_outputs   = { for name, vm in local.vm_outputs_by_name : name => vm if vm.role != "bastion" }
}

output "bastion_public_ips" {
  description = "Bastion public IPs by logical VM name."
  value       = { for name, vm in local.vm_outputs_by_name : name => vm.public_ip if vm.role == "bastion" }
}

output "bastion_public_ip" {
  description = "Bastion public IP."
  value       = try(local.vm_outputs_by_name["bastion"].public_ip, null)
}

output "workload_vm_names" {
  description = "VM names by workload."
  value = {
    for name, workload in local.workload_outputs : name => workload.name
  }
}

output "workload_roles" {
  description = "Roles by workload."
  value = {
    for name, workload in local.workload_outputs : name => workload.role
  }
}

output "workload_internal_ips" {
  description = "Internal IPs by workload."
  value = {
    for name, workload in local.workload_outputs : name => workload.internal_ip
  }
}

output "workload_external_ips" {
  description = "External IPs by workload."
  value = {
    for name, workload in local.workload_outputs : name => workload.public_ip
  }
}

output "workload_network_tags" {
  description = "GCP network tags by workload. AWS workloads return an empty list."
  value = {
    for name, workload in local.workload_outputs : name => workload.network_tags
  }
}

output "workload_identity_ids" {
  description = "GCP service-account email or AWS IAM role ARN by workload."
  value = {
    for name, workload in local.workload_outputs : name => workload.identity_id
  }
}

output "workload_service_account_emails" {
  description = "GCP service-account emails by workload; null for AWS workloads."
  value = {
    for name, workload in local.workload_outputs : name => workload.service_account_email
  }
}
