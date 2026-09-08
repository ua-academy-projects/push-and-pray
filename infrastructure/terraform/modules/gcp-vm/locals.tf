locals {
  context = {
    resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
    labels = merge(
      {
        application = var.config.name_prefix
        environment = var.config.environment
        managed_by  = "terraform"
      },
      var.config.common_labels,
    )
  }

  placed_vms = {
    for name, vm in var.config.vms : name => merge(vm, {
      location = lookup(vm, "location", var.config.default_location)
      labels   = merge(local.context.labels, try(vm.labels, {}))
    })
    if lookup(vm, "cloud", var.config.default_cloud) == "gcp"
  }

  vms = {
    for name, vm in local.placed_vms : name => merge(vm, {
      region       = var.config.locations[vm.location].gcp.region
      zone         = var.config.locations[vm.location].gcp.zone
      machine_type = var.config.machine_types[vm.machine_type].gcp
      image        = var.config.images[vm.image].gcp
      boot_disk = merge(vm.boot_disk, {
        type = var.config.disk_types[vm.boot_disk.disk_type].gcp.type
        iops = try(
          vm.boot_disk.iops,
          var.config.disk_types[vm.boot_disk.disk_type].gcp.iops,
          null,
        )
      })
      data_disks = {
        for disk_name, disk in try(vm.data_disks, {}) : disk_name => merge(disk, {
          type = var.config.disk_types[disk.disk_type].gcp.type
          iops = try(
            disk.iops,
            var.config.disk_types[disk.disk_type].gcp.iops,
            null,
          )
        })
      }
    })
  }

  data_disks = {
    for disk in flatten([
      for vm_name, vm in local.vms : [
        for disk_name, disk in vm.data_disks : merge(disk, {
          key       = "${vm_name}/${disk_name}"
          name      = "${local.context.resource_prefix}-${vm_name}-${disk_name}"
          disk_name = disk_name
          vm_name   = vm_name
          zone      = vm.zone
          labels    = vm.labels
        })
      ]
    ]) : disk.key => disk
  }
}
