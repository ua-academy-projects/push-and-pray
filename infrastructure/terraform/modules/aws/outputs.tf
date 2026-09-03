output "names" {
  value = local.has_vms ? module.vm[0].names : {}
}

output "private_ips" {
  value = local.has_vms ? module.vm[0].private_ips : {}
}

output "public_ips" {
  value = local.has_vms ? module.vm[0].public_ips : {}
}

output "workload_names" {
  description = "AWS workload VM names, excluding the bastion."
  value = local.has_vms ? {
    for name, vm in local.workload_vms : name => module.vm[0].names[name]
  } : {}
}

output "workload_roles" {
  description = "AWS workload roles, excluding the bastion."
  value = {
    for name, vm in local.workload_vms : name => vm.role
  }
}

output "workload_private_ips" {
  description = "AWS workload private IPs, excluding the bastion."
  value = local.has_vms ? {
    for name, vm in local.workload_vms : name => module.vm[0].private_ips[name]
  } : {}
}

output "workload_public_ips" {
  description = "AWS workload public IPs, excluding the bastion."
  value = local.has_vms ? {
    for name, vm in local.workload_vms : name => module.vm[0].public_ips[name]
  } : {}
}
