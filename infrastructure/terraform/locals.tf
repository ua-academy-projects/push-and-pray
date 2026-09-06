locals {
  config = jsondecode(file(var.project_config_path))

  vm_clouds = {
    for name, vm in local.config.vms : name => try(vm.cloud, local.config.default_cloud)
  }

  resolved_vms = {
    for name, vm in local.config.vms : name => merge(vm, {
      cloud            = local.vm_clouds[name]
      native_vm_type   = local.config.size_map[vm.size][local.vm_clouds[name]]
      native_disk_type = local.config.disk_type_map[vm.disk_type][local.vm_clouds[name]]
      native_image     = local.config.image_map[vm.image][local.vm_clouds[name]]
    })
  }

  gcp_vms = {
    for name, vm in local.resolved_vms : name => vm
    if vm.cloud == "gcp"
  }

  aws_vms = {
    for name, vm in local.resolved_vms : name => vm
    if vm.cloud == "aws"
  }

  native_region = local.config.region_map[local.config.region][local.config.default_cloud]

  bastion_vm = local.resolved_vms.bastion
  workload_vms = {
    for name, vm in local.resolved_vms : name => vm
    if vm.role != "bastion"
  }

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  common_labels = {
    application = local.config.name_prefix
    environment = local.config.environment
    managed_by  = "terraform"
  }
}
