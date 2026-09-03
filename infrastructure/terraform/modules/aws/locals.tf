locals {
  config = var.config

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  has_vms = length(local.resolved_vms) > 0

  bastion_vm = local.config.vms.bastion

  common_labels = merge(
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
      cloud       = var.cloud_key
    },
    local.config.common_labels,
  )

  effective_cloud_by_vm = {
    for name, vm in local.config.vms :
    name => lookup(vm, "cloud", local.config.default_cloud)
  }

  selected_raw_vms = {
    for name, vm in local.config.vms :
    name => vm
    if local.effective_cloud_by_vm[name] == var.cloud_key
  }

  resolved_vms = {
    for name, vm in local.selected_raw_vms :
    name => merge(vm, {
      effective_cloud = local.effective_cloud_by_vm[name]
      location        = local.config.regions[vm.region][var.cloud_key]
      instance_type   = local.config.sizes[vm.size][var.cloud_key]
      disk_type       = local.config.disk_types[vm.boot_disk.type][var.cloud_key]
      image_config    = local.config.images[vm.image][var.cloud_key]
    })
  }

  workload_vms = {
    for name, vm in local.resolved_vms :
    name => vm
    if vm.role != "bastion"
  }
}
