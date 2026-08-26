output "bastion_public_ip" {
  description = "Bastion public IP."
  value       = module.vm["bastion"].public_ip
}

output "workload_vm_names" {
  description = "VM names by workload."
  value = {
    for name, workload in local.workload_vms : name => module.vm[name].name
  }
}

output "workload_roles" {
  description = "Roles by workload."
  value = {
    for name, workload in local.workload_vms : name => workload.role
  }
}

output "workload_internal_ips" {
  description = "Internal IPs by workload."
  value = {
    for name, workload in local.workload_vms : name => module.vm[name].internal_ip
  }
}

output "workload_external_ips" {
  description = "External IPs by workload."
  value = {
    for name, workload in local.workload_vms : name => module.vm[name].public_ip
  }
}

output "workload_network_tags" {
  description = "Network tags by workload."
  value = {
    for name, workload in local.workload_vms : name => module.vm[name].network_tags
  }
}

output "workload_automation_roles" {
  description = "Automation roles by workload."
  value = {
    for name, workload in local.workload_vms : name => workload.automation_role
  }
}

output "workload_service_account_emails" {
  description = "Service-account emails by workload."
  value = {
    for name, workload in local.workload_vms : name => module.vm[name].service_account_email
  }
}
