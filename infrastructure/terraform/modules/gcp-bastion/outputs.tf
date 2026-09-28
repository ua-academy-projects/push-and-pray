output "public_ips" {
  description = "Static public IP address keyed by the bastion logical name."
  value       = module.vm.public_ips
}

output "instance_ids" {
  description = "Compute Engine instance ID keyed by the bastion logical name."
  value       = module.vm.instance_ids
}
