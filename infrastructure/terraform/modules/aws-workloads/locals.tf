locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  common_labels = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )

  placed_vms = {
    for name, vm in var.config.vms : name => merge(vm, {
      location = lookup(vm, "location", var.config.default_location)
      labels   = merge(local.common_labels, try(vm.labels, {}))
    })
    if lookup(vm, "cloud", var.config.default_cloud) == "aws"
  }

  vms = {
    for name, vm in local.placed_vms : name => merge(vm, {
      resource_name      = "${local.resource_prefix}-${name}"
      region             = var.config.locations[vm.location].aws.region
      machine_type       = var.config.machine_types[vm.machine_type].aws
      image              = var.config.images[vm.image].aws
      subnet_id          = vm.assign_public_ip ? var.networks[vm.location].public_subnet_id : var.networks[vm.location].private_subnet_id
      security_group_ids = [for tag in vm.tags : var.security_group_ids[vm.location][tag]]
      instance_profile   = var.instance_profiles[name]
      key_name           = var.bootstrap_key_names[vm.location]
      cloud_init         = null
      boot_disk = merge(vm.boot_disk, {
        type = var.config.disk_types[vm.boot_disk.disk_type].aws.type
        iops = try(vm.boot_disk.iops, var.config.disk_types[vm.boot_disk.disk_type].aws.iops, null)
      })
      data_disks = {
        for disk_name, disk in try(vm.data_disks, {}) : disk_name => merge(disk, {
          device_name = "/dev/sd${substr(
            "fghijklmnop",
            index(sort(keys(try(vm.data_disks, {}))), disk_name),
            1,
          )}"
          type = var.config.disk_types[disk.disk_type].aws.type
          iops = try(disk.iops, var.config.disk_types[disk.disk_type].aws.iops, null)
        })
      }
    })
  }
}
