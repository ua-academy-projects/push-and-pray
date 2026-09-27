locals {
  cloud_name              = "azure"
  cloud_config            = lookup(var.config.clouds, local.cloud_name, {})
  resource_prefix         = join("-", compact(["${var.config.name_prefix}-${var.config.environment}", var.name_suffix]))
  location_key            = var.region_key
  zone                    = try(local.cloud_config.zones[var.region_key], null)
  images                  = lookup(lookup(local.cloud_config, "images", {}), local.location_key, {})
  minimum_os_disk_size_gb = 30
  common_tags = merge(var.config.common_labels, {
    application       = var.config.name_prefix
    environment       = var.config.environment
    managed_by        = "terraform"
    cloud             = local.cloud_name
    deployment_region = var.region_key
  })
  resolved_vms = {
    for name, vm in var.vms : name => merge(vm, {
      machine_type = local.cloud_config.machine_types[vm.machine_type]
      image        = local.images[vm.image]
      internal_ip  = lookup(lookup(vm, "internal_ips", {}), local.cloud_name, vm.internal_ip)
      boot_disk = merge(vm.boot_disk, {
        type    = local.cloud_config.disk_types[vm.boot_disk.type]
        size_gb = max(vm.boot_disk.size_gb, local.minimum_os_disk_size_gb)
      })
    })
  }
  primary_ssh_user = try(sort(keys(var.config.ssh_users))[0], null)
  disks = merge({}, [
    for vm_name, vm in local.resolved_vms : {
      for disk_name, disk in lookup(vm, "additional_disks", {}) :
      "${vm_name}-${disk_name}" => merge(disk, {
        vm_name = vm_name
        lun     = index(sort(keys(lookup(vm, "additional_disks", {}))), disk_name)
        type    = local.cloud_config.disk_types[disk.type]
      })
    }
  ]...)
}
