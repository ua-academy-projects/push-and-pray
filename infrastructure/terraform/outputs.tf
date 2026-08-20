output "bastion_public_ip" {
  description = "Bastion public IP."
  value       = module.bastion.public_ip
}

output "workload_vm_names" {
  description = "VM names by workload."
  value = {
    for name, vm in module.vm : name => vm.name
  }
}

output "workload_roles" {
  description = "Roles by workload."
  value = {
    for name, workload in local.config.workloads : name => workload.role
  }
}

output "workload_internal_ips" {
  description = "Internal IPs by workload."
  value = {
    for name, vm in module.vm : name => vm.internal_ip
  }
}

output "workload_external_ips" {
  description = "External IPs by workload."
  value = {
    for name, vm in module.vm : name => vm.public_ip
  }
}

output "workload_network_tags" {
  description = "Network tags by workload."
  value = {
    for name, vm in module.vm : name => vm.network_tags
  }
}

output "workload_automation_roles" {
  description = "Automation roles by workload."
  value = {
    for name, workload in local.config.workloads : name => workload.automation_role
  }
}

output "workload_service_account_emails" {
  description = "Service-account emails by workload."
  value = {
    for name, vm in module.vm : name => vm.service_account_email
  }
}
