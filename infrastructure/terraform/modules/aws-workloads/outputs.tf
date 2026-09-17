output "public_ips" {
  description = "Static public IP addresses keyed by logical workload VM name."
  value       = module.vm.public_ips
}

output "instance_ids" {
  description = "EC2 instance IDs keyed by logical workload VM name."
  value       = module.vm.instance_ids
}

output "volume_ids" {
  description = "EBS volume IDs keyed by logical workload VM and disk name."
  value       = module.vm.volume_ids
}
