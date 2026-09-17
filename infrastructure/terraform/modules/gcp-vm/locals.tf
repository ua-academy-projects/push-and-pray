locals {
  cloud_name      = "gcp"
  cloud_config    = lookup(var.config.clouds, local.cloud_name, {})
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
  images = lookup(lookup(local.cloud_config, "images", {}), var.config.location.region, {})
  resolved_vms = {
    for name, vm in local.vms : name => merge(vm, {
      machine_type = local.cloud_config.machine_types[vm.machine_type]
      image        = local.images[vm.image]
      internal_ip  = lookup(lookup(vm, "internal_ips", {}), local.cloud_name, vm.internal_ip)
      boot_disk = merge(vm.boot_disk, {
        type = local.cloud_config.disk_types[vm.boot_disk.type]
      })
    })
  }
  disks = merge({}, [
    for vm_name, vm in local.vms : {
      for disk_name, disk in lookup(vm, "additional_disks", {}) :
      "${vm_name}-${disk_name}" => disk
    }
  ]...)
}
