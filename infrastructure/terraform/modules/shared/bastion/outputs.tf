output "vm" {
  description = "The bastion's specification, shaped like an entry of the project configuration's vms map so a cloud's VM module accepts it unchanged."
  value       = local.vm
}

output "internal_ip" {
  description = "The address derived from the management subnet, exposed on its own for callers that need it before the VM exists."
  value       = local.vm.internal_ip
}

output "ssh_port" {
  description = "Port the bastion's SSH daemon will listen on once Ansible has configured it."
  value       = local.bastion.ssh_port
}

output "allowed_cidrs" {
  description = "Source ranges permitted to reach the bastion, for the firewall module."
  value       = local.bastion.allowed_cidrs
}
