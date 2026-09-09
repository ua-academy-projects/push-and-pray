output "enabled" {
  description = "Whether AWS CPU monitoring resources are enabled."
  value       = local.enabled
}

output "monitored_vm_names" {
  description = "Names of Terraform-managed VMs covered by AWS CPU monitoring."
  value       = sort([for vm in values(local.vms) : vm.name])
}
