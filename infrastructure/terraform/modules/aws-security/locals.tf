locals {
  cloud_name      = "aws"
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  vms = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == local.cloud_name
  }
  common_tags = merge(var.config.common_labels, {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud_name
  })
  bastion_names = sort([
    for name, vm in local.vms : name
    if vm.role == "bastion"
  ])
  bastion_name = try(local.bastion_names[0], null)

  ui_names = sort([
    for name, vm in local.vms : name
    if vm.role == "ui"
  ])
  history_names = sort([
    for name, vm in local.vms : name
    if vm.role == "history"
  ])
  database_names = sort([
    for name, vm in local.vms : name
    if vm.role == "database"
  ])

  bastion_ssh_rules = {
    for rule in flatten([
      for name, vm in local.vms : [
        for index, cidr in lookup(vm, "allowed_cidrs", []) : {
          key     = "${name}-${index}"
          vm_name = name
          cidr    = cidr
          port    = lookup(vm, "ssh_port", 22)
        }
      ] if vm.role == "bastion"
    ]) : rule.key => rule
  }

  ui_web_rules = {
    for rule in flatten([
      for name, vm in local.vms : [
        for port in var.config.network.ui_public_ports : {
          key     = "${name}-${port}"
          vm_name = name
          port    = port
        }
      ] if vm.role == "ui"
    ]) : rule.key => rule
  }

  workload_ssh_targets = {
    for name, vm in local.vms : name => vm
    if local.bastion_name != null && vm.role != "bastion"
  }

  history_api_rules = {
    for pair in setproduct(local.ui_names, local.history_names) :
    "${pair[0]}-${pair[1]}" => {
      source = pair[0]
      target = pair[1]
    }
  }

  postgresql_sources = sort([
    for name, vm in local.vms : name
    if contains(["history", "fetcher", "ui"], vm.role)
  ])

  postgresql_rules = {
    for pair in setproduct(local.postgresql_sources, local.database_names) :
    "${pair[0]}-${pair[1]}" => {
      source = pair[0]
      target = pair[1]
    } if var.database_mode == "self_hosted"
  }

  rabbitmq_sources = sort([
    for name, vm in local.vms : name
    if contains(["history", "fetcher"], vm.role)
  ])

  rabbitmq_rules = {
    for pair in setproduct(local.rabbitmq_sources, local.database_names) :
    "${pair[0]}-${pair[1]}" => {
      source = pair[0]
      target = pair[1]
    } if var.database_mode == "managed"
  }
}
