locals {
  vm_outputs_by_name = merge(
    {
      for name, vm in module.gcp_vm : name => {
        name                  = vm.name
        internal_ip           = vm.internal_ip
        public_ip             = vm.public_ip
        network_tags          = vm.network_tags
        identity_id           = vm.service_account_email
        service_account_email = vm.service_account_email
      }
    },
    {
      for name, vm in module.aws_vm : name => {
        name                  = vm.name
        internal_ip           = vm.internal_ip
        public_ip             = vm.public_ip
        network_tags          = []
        identity_id           = vm.iam_role_arn
        service_account_email = null
      }
    },
  )
}

output "bastion_public_ip" {
  description = "Bastion public IP."
  value       = local.vm_outputs_by_name["bastion"].public_ip
}

output "workload_vm_names" {
  description = "VM names by workload."
  value = {
    for name, workload in local.workload_vms :
    name => local.vm_outputs_by_name[name].name
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
    for name, workload in local.workload_vms :
    name => local.vm_outputs_by_name[name].internal_ip
  }
}

output "workload_external_ips" {
  description = "External IPs by workload."
  value = {
    for name, workload in local.workload_vms :
    name => local.vm_outputs_by_name[name].public_ip
  }
}

output "workload_network_tags" {
  description = "GCP network tags by workload. AWS workloads return an empty list."
  value = {
    for name, workload in local.workload_vms :
    name => local.vm_outputs_by_name[name].network_tags
  }
}

output "workload_identity_ids" {
  description = "GCP service-account email or AWS IAM role ARN by workload."
  value = {
    for name, workload in local.workload_vms :
    name => local.vm_outputs_by_name[name].identity_id
  }
}

output "workload_service_account_emails" {
  description = "GCP service-account emails by workload; null for AWS workloads."
  value = {
    for name, workload in local.workload_vms :
    name => local.vm_outputs_by_name[name].service_account_email
  }
}

output "secret_ids" {
  description = "Secret Manager container IDs created from the project configuration."
  value       = sort(local.all_secret_ids)
}

output "secret_resource_names" {
  description = "GCP Secret Manager resource names by secret ID, retained for compatibility."
  value       = try(module.gcp_secrets[0].secret_resource_names, {})
}

output "secret_resource_names_by_cloud" {
  description = "Secret resource names grouped by cloud and secret ID."
  value = {
    gcp = try(module.gcp_secrets[0].secret_resource_names, {})
    aws = try(module.aws_secrets[0].secret_resource_names, {})
  }
}

output "workload_secret_access" {
  description = "Secret IDs each workload service account may read. Names only - never values."
  value = {
    for name, workload in local.workload_vms :
    name => sort(distinct(values(workload.secret_mappings)))
  }
}
