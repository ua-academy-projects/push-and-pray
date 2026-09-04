output "default_cloud" {
  description = "Default cloud selected by the shared project configuration."
  value       = jsondecode(file(var.project_config_path)).default_cloud
}

output "vms" {
  description = "Provider-neutral VM inventory keyed by project-config VM key."
  value       = merge(module.gcp.vms, module.aws.vms)

  precondition {
    condition     = module.gcp.configuration_valid && module.aws.configuration_valid
    error_message = "Every VM cloud override and its machine, image, disk and location profiles must resolve from the shared configuration."
  }
}

output "bastion_public_ip" {
  description = "Public IP of the default-cloud bastion, or null when absent."
  value = try([
    for vm in values(merge(module.gcp.vms, module.aws.vms)) :
    vm.public_ip
    if vm.role == "bastion" && vm.cloud == jsondecode(file(var.project_config_path)).default_cloud
  ][0], null)
}

output "workload_vm_names" {
  description = "VM names by workload."
  value = {
    for name, vm in merge(module.gcp.vms, module.aws.vms) :
    name => vm.name if vm.role != "bastion"
  }
}

output "workload_roles" {
  description = "Roles by workload."
  value = {
    for name, vm in merge(module.gcp.vms, module.aws.vms) :
    name => vm.role if vm.role != "bastion"
  }
}

output "workload_internal_ips" {
  description = "Internal IPs by workload."
  value = {
    for name, vm in merge(module.gcp.vms, module.aws.vms) :
    name => vm.internal_ip if vm.role != "bastion"
  }
}

output "workload_external_ips" {
  description = "External IPs by workload."
  value = {
    for name, vm in merge(module.gcp.vms, module.aws.vms) :
    name => vm.public_ip if vm.role != "bastion"
  }
}

output "workload_network_tags" {
  description = "Provider-native network selectors by workload."
  value = {
    for name, vm in merge(module.gcp.vms, module.aws.vms) :
    name => vm.network_tags if vm.role != "bastion"
  }
}

output "workload_identities" {
  description = "GCP service-account email or AWS IAM role ARN by workload."
  value = {
    for name, vm in merge(module.gcp.vms, module.aws.vms) :
    name => vm.runtime_identity if vm.role != "bastion"
  }
}

output "workload_service_account_emails" {
  description = "Backward-compatible GCP-only service-account emails."
  value = {
    for name, vm in module.gcp.vms :
    name => vm.runtime_identity
    if vm.role != "bastion"
  }
}

output "secret_ids" {
  description = "Secret IDs referenced by at least one workload."
  value       = sort(distinct(concat(module.gcp.secret_ids, module.aws.secret_ids)))
}

output "secret_resource_names" {
  description = "Provider-native secret resource names, keyed by cloud and secret ID."
  value = {
    gcp = module.gcp.secret_resource_names
    aws = module.aws.secret_resource_names
  }
}

output "workload_secret_access" {
  description = "Secret IDs each workload identity may read; never values."
  value       = merge(module.gcp.workload_secret_access, module.aws.workload_secret_access)
}
