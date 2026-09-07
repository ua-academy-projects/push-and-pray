locals {
  selected_vms = {
    for name, vm in var.config.vms : name => vm
    if try(vm.cloud, var.config.default_cloud) == "aws"
  }

  resolved_vms = {
    for name, vm in local.selected_vms : name => merge(vm, {
      name       = "${var.resource_prefix}-${name}"
      cloud      = "aws"
      region_key = try(vm.region, var.config.default_region)
      provider_region = var.config.cloud_mappings.regions[
        try(vm.region, var.config.default_region)
      ].aws.region
      provider_zone = var.config.cloud_mappings.regions[
        try(vm.region, var.config.default_region)
      ].aws.zone
      machine_type   = var.config.cloud_mappings.sizes[vm.size].aws
      disk_type      = var.config.cloud_mappings.disk_types[vm.boot_disk.type].aws
      image_settings = var.config.cloud_mappings.images[vm.image].aws
      labels = merge(var.common_labels, try(vm.labels, {}), {
        application = var.config.name_prefix
        environment = var.config.environment
        managed_by  = "terraform"
        role        = vm.role
        cloud       = "aws"
      })
    })
  }

  public_vms = { for name, vm in local.resolved_vms : name => vm if vm.assign_public_ip }
}
