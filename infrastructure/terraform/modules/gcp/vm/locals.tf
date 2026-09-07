locals {
  vm_clouds = {
    for name, vm in var.config.vms : name => try(vm.cloud, var.config.default_cloud)
  }

  resolved_vms = {
    for name, vm in var.config.vms : name => merge(vm, {
      cloud            = local.vm_clouds[name]
      native_vm_type   = var.config.size_map[vm.size][local.vm_clouds[name]]
      native_disk_type = var.config.disk_type_map[vm.disk_type][local.vm_clouds[name]]
      native_image     = var.config.image_map[vm.image][local.vm_clouds[name]]
    })
  }

  gcp_vms = {
    for name, vm in local.resolved_vms : name => vm
    if vm.cloud == "gcp"
  }

  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  common_labels = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }

  vm_names = {
    for name, vm in local.gcp_vms : name => "${local.resource_prefix}-${name}"
  }

  vm_labels = {
    for name, vm in local.gcp_vms : name => merge(
      local.common_labels,
      try(vm.labels, {}),
      { role = vm.role },
    )
  }

  subnetwork_ids = {
    for name, vm in local.gcp_vms : name => (
      vm.role == "bastion"
      ? var.network.management_subnet_id
      : var.network.workload_subnet_id
    )
  }

  vm_network_tags = {
    for name, vm in local.gcp_vms : name => [
      for tag in vm.network_tags : "${local.resource_prefix}-${tag}"
    ]
  }
}
