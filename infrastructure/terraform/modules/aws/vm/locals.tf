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

  aws_vms = {
    for name, vm in local.resolved_vms : name => vm
    if vm.cloud == "aws"
  }

  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  common_labels = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }

  vm_labels = {
    for name, vm in local.aws_vms : name => merge(
      local.common_labels,
      try(vm.labels, {}),
      { role = vm.role },
    )
  }

  subnet_ids = {
    for name, vm in local.aws_vms : name => (
      contains(["bastion", "ui"], vm.role)
      ? var.network.management_subnet_id
      : var.network.workload_subnet_id
    )
  }

  security_group_ids = {
    for name, vm in local.aws_vms : name => var.network.security_group_ids[vm.role]
  }

  cloud_init_user_data = templatefile("${path.module}/../templates/ssh-users.yaml.tfpl", {
    ssh_users = var.config.ssh_users
  })
}
