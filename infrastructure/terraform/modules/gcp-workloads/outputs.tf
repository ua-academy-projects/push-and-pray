output "public_ips" {
  description = "Static public IP addresses keyed by logical workload VM name."
  value       = module.vm.public_ips
}

output "instance_ids" {
  description = "Compute Engine instance IDs keyed by logical workload VM name."
  value       = module.vm.instance_ids
}
