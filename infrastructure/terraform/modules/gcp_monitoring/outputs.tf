output "enabled" {
  description = "Whether any supported GCP monitoring resources are enabled."
  value       = local.enabled
}

output "monitored_vm_names" {
  description = "Names of Terraform-managed VMs covered by GCP monitoring."
  value       = sort([for vm in values(var.vms) : vm.name if local.enabled])
}

output "http_5xx_enabled" {
  description = "Whether GCP HTTP 5xx monitoring is enabled for a GCP UI VM."
  value       = local.http_5xx_enabled
}
