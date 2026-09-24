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

  azure_vms = {
    for name, vm in local.resolved_vms : name => vm
    if vm.cloud == "azure"
  }

  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  common_tags = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }

  vm_names = {
    for name, vm in local.azure_vms : name => "${local.resource_prefix}-${name}"
  }

  vm_tags = {
    for name, vm in local.azure_vms : name => merge(
      local.common_tags,
      try(vm.labels, {}),
      { role = vm.role },
    )
  }

  admin_username = try(var.config.clouds.azure.admin_username, null)
  zone           = var.config.region_map[var.config.region]["azure"].availability_zone

  cloud_init_user_data = {
    for name, vm in local.azure_vms : name => templatefile("${path.module}/templates/cloud-init.yaml.tfpl", {
      ssh_users = var.config.ssh_users
      ssh_port  = vm.role == "bastion" ? vm.ssh_port : null
    })
  }
}
