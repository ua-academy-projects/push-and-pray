output "bastion_public_ip" {
  description = "Static external IP address of the bastion VM."
  value       = module.bastion.public_ip
}

output "ui_public_ip" {
  description = "Static external IP address of the UI VM."
  value       = module.vm["ui"].public_ip
}

output "workload_internal_ips" {
  description = "Internal IP addresses of workload VMs, keyed by role."

  value = {
    for role, vm in module.vm :
    role => vm.internal_ip
  }
}