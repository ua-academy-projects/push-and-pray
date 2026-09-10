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
    if lookup(vm, "cloud", var.config.default_cloud) == "aws"
  }

  vms = {
    for name, vm in local.placed_vms : name => merge(vm, {
      region       = var.config.locations[vm.location].aws.region
      machine_type = var.config.machine_types[vm.machine_type].aws
      image        = var.config.images[vm.image].aws
      cloud_init = contains(vm.tags, "bastion") ? templatefile(
        "${path.root}/templates/bastion-cloud-config.yaml.tftpl",
        { ssh_port = vm.ssh_port },
      ) : null
      boot_disk = merge(vm.boot_disk, {
        type = var.config.disk_types[vm.boot_disk.disk_type].aws.type
        iops = try(
          vm.boot_disk.iops,
          var.config.disk_types[vm.boot_disk.disk_type].aws.iops,
          null,
        )
      })
      data_disks = {
        for disk_name, disk in try(vm.data_disks, {}) : disk_name => merge(disk, {
          device_name = "/dev/sd${substr(
            "fghijklmnop",
            index(sort(keys(try(vm.data_disks, {}))), disk_name),
            1,
          )}"
          type = var.config.disk_types[disk.disk_type].aws.type
          iops = try(
            disk.iops,
            var.config.disk_types[disk.disk_type].aws.iops,
            null,
          )
        })
      }
    })
  }

  bootstrap_ssh_public_key = var.config.ssh_users[sort(keys(var.config.ssh_users))[0]]
}
