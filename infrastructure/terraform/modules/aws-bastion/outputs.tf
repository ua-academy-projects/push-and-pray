output "public_ips" {
  description = "Static public IP address keyed by the bastion logical name."
  value       = module.vm.public_ips
}

output "instance_ids" {
  description = "EC2 instance ID keyed by the bastion logical name."
  value       = module.vm.instance_ids
}

output "volume_ids" {
  description = "EBS volume IDs keyed by the bastion logical name and disk name."
  value       = module.vm.volume_ids
}
