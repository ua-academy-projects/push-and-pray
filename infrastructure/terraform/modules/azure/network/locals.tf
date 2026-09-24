locals {
  postgres_enabled = var.config.default_cloud == "azure" && var.config.managed_database

  budget_enabled = try(var.config.budgets.azure.enabled, false)

  enabled = anytrue([
    for vm in values(var.config.vms) : try(vm.cloud, var.config.default_cloud) == "azure"
  ]) || local.postgres_enabled || local.budget_enabled

  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  location        = var.config.region_map[var.config.region]["azure"].location

  common_tags = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }

  azure_vms = {
    for name, vm in var.config.vms : name => vm
    if try(vm.cloud, var.config.default_cloud) == "azure"
  }

  roles = ["bastion", "database", "history", "fetcher", "ui"]

  ui_public_ports = [
    for port in var.config.network.ui_public_ports : tostring(port)
  ]

  subnet_cidrs = {
    management = var.config.network.management_subnet_cidr
    workload   = var.config.network.workload_subnet_cidr
  }

  subnet_bounds = {
    for key, cidr in local.subnet_cidrs : key => {
      first = sum([for i, octet in split(".", cidrhost(cidr, 0)) : tonumber(octet) * pow(256, 3 - i)])
      last  = sum([for i, octet in split(".", cidrhost(cidr, -1)) : tonumber(octet) * pow(256, 3 - i)])
    }
  }

  vm_subnets = {
    for name, vm in local.azure_vms : name => one([
      for key, bounds in local.subnet_bounds : key
      if sum([for i, octet in split(".", vm.internal_ip) : tonumber(octet) * pow(256, 3 - i)]) > bounds.first + 3
      && sum([for i, octet in split(".", vm.internal_ip) : tonumber(octet) * pow(256, 3 - i)]) < bounds.last
    ])
  }

  nat_subnets = toset([
    for name, vm in local.azure_vms : local.vm_subnets[name]
    if !vm.assign_public_ip && local.vm_subnets[name] != null
  ])
}
