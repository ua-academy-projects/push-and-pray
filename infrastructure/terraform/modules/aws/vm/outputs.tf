output "names" {
  description = "Names of workload VMs, by VM key."
  value       = { for name, vm in aws_instance.workload : name => "${local.resource_prefix}-${name}" }
}

output "internal_ips" {
  description = "Internal IP addresses of workload VMs, by VM key."
  value       = { for name, vm in aws_instance.workload : name => vm.private_ip }
}

output "public_ips" {
  description = "Static public IP addresses, or null when none is assigned, by VM key."
  value = {
    for name, vm in local.selected_vms :
    name => vm.assign_public_ip ? var.public_ips[name] : null
  }
}

output "network_tags" {
  description = "Effective network tags of workload VMs, by VM key."
  value       = { for name, vm in local.selected_vms : name => vm.network_tags }
}
