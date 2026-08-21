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

output "workload_names" {
  description = "Workload VM names keyed by workload configuration key."
  value = {
    for workload_name, vm in module.vm : workload_name => vm.name
  }
}

output "workload_service_accounts" {
  description = "Workload service account emails keyed by workload configuration key."
  value = {
    for workload_name, vm in module.vm : workload_name => vm.service_account_email
  }
}

output "workload_roles" {
  description = "Configured workload roles keyed by workload configuration key."
  value = {
    for workload_name, workload in local.config.workloads : workload_name => workload.role
  }
}

output "workload_automation_roles" {
  description = "Configured automation roles keyed by workload configuration key."
  value = {
    for workload_name, workload in local.config.workloads : workload_name => workload.automation_role
  }
}