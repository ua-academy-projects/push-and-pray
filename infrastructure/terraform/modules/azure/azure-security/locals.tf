locals {
  cloud_name      = "azure"
  resource_prefix = join("-", compact(["${var.config.name_prefix}-${var.config.environment}", var.name_suffix]))
  common_tags = merge(var.config.common_labels, {
    application       = var.config.name_prefix
    environment       = var.config.environment
    managed_by        = "terraform"
    cloud             = local.cloud_name
    deployment_region = var.region_key
  })
  network = var.network

  bastion_ssh_rules = {
    for rule in flatten([
      for name, vm in var.vms : [
        for index, cidr in lookup(vm, "allowed_cidrs", []) : {
          key      = "${name}-${index}"
          vm_name  = name
          cidr     = cidr
          port     = lookup(vm, "ssh_port", 22)
          priority = 100 + index
        }
      ] if vm.role == "bastion"
    ]) : rule.key => rule
  }
  workload_ssh_targets = {
    for name, vm in var.vms : name => vm if vm.role != "bastion"
  }
  public_endpoint_targets = {
    for name, vm in var.vms : name => vm
    if try(vm.public_endpoint.hostname, null) != null
  }
  history_targets = {
    for name, vm in var.vms : name => vm if vm.role == "history"
  }
  database_targets = {
    for name, vm in var.vms : name => vm if vm.role == "database"
  }
  k3s_targets = {
    for name, vm in var.vms : name => vm if vm.role == "k3s"
  }
  k3s_server_targets = {
    for name, vm in local.k3s_targets : name => vm if vm.k3s_role == "server"
  }
}
