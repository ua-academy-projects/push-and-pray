output "enabled" {
  description = "Whether any supported AWS monitoring resources are enabled."
  value       = local.enabled
}

output "monitored_vm_names" {
  description = "Names of Terraform-managed VMs covered by AWS monitoring."
  value       = sort([for vm in values(var.vms) : vm.name if local.enabled])
}
