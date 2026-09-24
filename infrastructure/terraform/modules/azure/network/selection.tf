locals {
  managed_database_enabled = var.config.database_mode == "managed" && var.config.default_cloud == "azure"
  resource_prefix          = "${var.config.name_prefix}-${var.config.environment}"
  labels                   = merge(var.config.common_labels, { environment = var.config.environment })

  azure_vms = {
    for name, vm in var.config.vms : name => merge(
      { location = var.config.default_location, assign_public_ip = false, ssh_port = 22, allowed_cidrs = ["0.0.0.0/0"] },
      var.config.vm_defaults,
      vm,
    ) if try(vm.cloud, var.config.default_cloud) == "azure"
  }
  workload_locations = setunion(toset([
    for vm in values(local.azure_vms) : vm.location if vm.role != "bastion"
  ]), local.managed_database_enabled ? toset([var.config.default_location]) : toset([]))
  vms = {
    for name, vm in local.azure_vms : name => vm if contains(local.workload_locations, vm.location)
  }
  locations = {
    for location in local.workload_locations : location => var.config.locations[location].azure
  }
  location_suffixes = {
    for location in keys(local.locations) : location => location == var.config.default_location ? "" : "-${location}"
  }
  database_client_ips = [
    for vm in values(local.vms) : vm.internal_ip
    if vm.location == var.config.default_location && contains(["database", "history"], vm.role)
  ]
}
