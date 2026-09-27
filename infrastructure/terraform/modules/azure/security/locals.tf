locals {
  vms_by_role = {
    for name, vm in var.vms : vm.role => merge(vm, { config_key = name })
  }

  workload_vms = {
    for name, vm in var.vms : name => vm
    if vm.role != "bastion"
  }

  bastion_ip = try(local.vms_by_role.bastion.internal_ip, null)

  infrastructure_vm       = try(var.vms[var.infrastructure_vm_name], null)
  infrastructure_nsg_role = try(local.infrastructure_vm.role, null)

  self_managed_database_sources = var.managed_database_enabled ? {} : {
    for role in ["fetcher", "history", "ui"] : role => local.vms_by_role[role].internal_ip
    if contains(keys(local.vms_by_role), role) && contains(keys(local.vms_by_role), "database")
  }

  rabbitmq_sources = var.managed_database_enabled ? {
    for role in ["fetcher", "history"] : role => local.vms_by_role[role].internal_ip
    if contains(keys(local.vms_by_role), role) && local.infrastructure_vm != null
  } : {}

  redis_sources = var.managed_database_enabled && contains(keys(local.vms_by_role), "ui") && local.infrastructure_vm != null ? {
    ui = local.vms_by_role.ui.internal_ip
  } : {}
}
