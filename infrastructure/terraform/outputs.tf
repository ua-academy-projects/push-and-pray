locals {
  vm_outputs_by_name = merge(module.gcp_vm.vms, module.aws_vm.vms, module.azure_vm.vms)
  workload_outputs   = { for name, vm in local.vm_outputs_by_name : name => vm if vm.role != "bastion" }
}

output "database_mode" {
  description = "Selected application database architecture."
  value       = local.config.database_mode
}

output "managed_database" {
  description = "Non-secret managed PostgreSQL metadata consumed by Ansible inventory."
  value = local.config.database_mode == "managed" ? (
    local.config.default_cloud == "aws" ? module.aws_database.database : (
      local.config.default_cloud == "azure" ? module.azure_database.database : module.gcp_database.database
    )
  ) : null
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
  description = "GCP network tags by workload. AWS and Azure workloads return an empty list."
  value = {
    for name, workload in local.workload_outputs : name => workload.network_tags
  }
}

output "workload_identity_ids" {
  description = "GCP service-account email or AWS IAM role ARN by workload; null for Azure."
  value = {
    for name, workload in local.workload_outputs : name => workload.identity_id
  }
}

output "workload_service_account_emails" {
  description = "GCP service-account emails by workload; null for AWS and Azure workloads."
  value = {
    for name, workload in local.workload_outputs : name => workload.service_account_email
  }
}

output "ui_public_url" {
  description = "Cloudflare-managed public UI URL, or null when Cloudflare is disabled."
  value       = local.cloudflare.enabled ? "https://${local.cloudflare.hostname}" : null
}

output "vms" {
  description = "All VMs with common cloud, role, address, and SSH metadata."
  value = {
    for name, vm in local.vm_outputs_by_name : name => merge(vm, {
      cloud    = try(local.config.vms[name].cloud, local.config.default_cloud)
      ssh_user = try(local.config.vms[name].cloud, local.config.default_cloud) == "aws" ? "ubuntu" : one(keys(local.config.ssh_users))
      ssh_port = try(local.config.vms[name].ssh_port, 22)
    })
  }
}
