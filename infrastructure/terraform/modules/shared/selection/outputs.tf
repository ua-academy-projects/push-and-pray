output "profile" {
  description = "This cloud's profile from the configuration, or null when it declares none."
  value       = local.profile
}

output "is_active" {
  description = "Whether this cloud hosts any workload. False means the caller builds nothing at all."
  value       = local.is_active
}

output "my_vms" {
  description = "VMs the calling module manages. Empty unless the cloud is active."
  value       = local.my_vms
}

output "workload_vms" {
  description = "Managed VMs that are not bastions."
  value       = local.workload_vms
}

output "bastion_vms" {
  description = "Managed VMs that are bastions."
  value       = local.bastion_vms
}

output "bastion_vm" {
  description = "The single bastion of this cloud, or null when it is inactive."
  value       = one(values(local.bastion_vms))
}

output "resource_prefix" {
  description = "Prefix shared by every resource name."
  value       = "${var.config.name_prefix}-${var.config.environment}"
}

output "common_labels" {
  description = "Labels or tags applied to every resource, including the cloud key the Ansible inventory selects on."
  value       = local.common_labels
}

output "cloud" {
  description = "The cloud this instance of the module answered for."
  value       = var.cloud
}

output "cloud_vms" {
  description = "Every VM the configuration assigns to this cloud, whether or not it is built. Compare with my_vms to see what the active check dropped."
  value       = local.cloud_vms
}

output "skipped_vms" {
  description = "VMs assigned to this cloud that are deliberately not built, because the cloud hosts no workload. Empty whenever the cloud is active."
  value = {
    for name, vm in local.cloud_vms : name => vm
    if !local.is_active
  }
}
