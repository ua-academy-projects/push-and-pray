output "public_ips" {
  description = "Static public IP address keyed by the Azure bastion logical name."
  value       = module.vm.public_ips
}

output "instance_ids" {
  description = "Azure VM ID keyed by the bastion logical name."
  value       = module.vm.instance_ids
}
