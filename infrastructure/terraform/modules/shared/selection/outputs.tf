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
