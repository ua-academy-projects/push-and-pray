locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  common_tags = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )
  admin_username = sort(keys(var.config.ssh_users))[0]

  placed_vms = {
    for name, vm in var.config.vms : name => merge(vm, {
      location = lookup(vm, "location", var.config.default_location)
    })
    if lookup(vm, "cloud", var.config.default_cloud) == "azure"
  }

  vms = {
    for name, vm in local.placed_vms : name => merge(vm, {
      resource_name             = "${local.resource_prefix}-${name}"
      region                    = var.config.locations[vm.location].azure.region
      zone                      = try(var.config.locations[vm.location].azure.zone, null)
      machine_type              = var.config.machine_types[vm.machine_type].azure
      image                     = var.config.images[vm.image].azure
      subnet_id                 = vm.assign_public_ip ? var.networks[vm.location].public_subnet_id : var.networks[vm.location].private_subnet_id
      network_security_group_id = var.network_security_group_ids[vm.location][one(vm.tags)]
      identity_id               = var.identity_ids[name]
      admin_username            = local.admin_username
      ssh_public_key            = var.config.ssh_users[local.admin_username]
      cloud_init                = null
      tags = merge(local.common_tags, try(vm.labels, {}), {
        Name           = "${local.resource_prefix}-${name}"
        FunctionalTags = join(",", sort(vm.tags))
      })
      boot_disk = merge(vm.boot_disk, {
        type = var.config.disk_types[vm.boot_disk.disk_type].azure.type
      })
      data_disks = {
        for disk_name, disk in try(vm.data_disks, {}) : disk_name => merge(disk, {
          type = var.config.disk_types[disk.disk_type].azure.type
        })
      }
    })
  }
}
