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
  ssh_metadata = {
    "enable-oslogin" = "FALSE"
    "ssh-keys" = join("\n", [
      for username, public_key in var.config.ssh_users :
      "${username}:${trimspace(public_key)}"
    ])
  }

  placed_vms = {
    for name, vm in var.config.vms : name => merge(vm, {
      location = lookup(vm, "location", var.config.default_location)
      labels   = merge(local.common_labels, try(vm.labels, {}))
    })
    if lookup(vm, "cloud", var.config.default_cloud) == "gcp"
  }

  vms = {
    for name, vm in local.placed_vms : name => merge(vm, {
      resource_name         = "${local.resource_prefix}-${name}"
      region                = var.config.locations[vm.location].gcp.region
      zone                  = var.config.locations[vm.location].gcp.zone
      machine_type          = var.config.machine_types[vm.machine_type].gcp
      image                 = var.config.images[vm.image].gcp
      subnet_id             = vm.assign_public_ip ? var.networks[vm.location].public_subnet_id : var.networks[vm.location].private_subnet_id
      provider_tags         = [for tag in vm.tags : "${local.resource_prefix}-${vm.location}-${tag}"]
      service_account_email = var.service_account_emails[name]
      metadata              = local.ssh_metadata
      cloud_init            = null
      boot_disk = merge(vm.boot_disk, {
        type = var.config.disk_types[vm.boot_disk.disk_type].gcp.type
        iops = try(vm.boot_disk.iops, var.config.disk_types[vm.boot_disk.disk_type].gcp.iops, null)
      })
      data_disks = {
        for disk_name, disk in try(vm.data_disks, {}) : disk_name => merge(disk, {
          type = var.config.disk_types[disk.disk_type].gcp.type
          iops = try(disk.iops, var.config.disk_types[disk.disk_type].gcp.iops, null)
        })
      }
    })
  }
}
