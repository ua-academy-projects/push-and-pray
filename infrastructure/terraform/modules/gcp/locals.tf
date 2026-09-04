locals {
  cloud = "gcp"

  selected_vms = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == local.cloud
  }

  enabled = length(local.selected_vms) > 0

  region = lookup(
    lookup(var.config.regions, var.config.location, {}),
    local.cloud,
    null,
  )

  zone = local.enabled ? sort(data.google_compute_zones.available[0].names)[0] : null

  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  common_labels = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )

  vms = {
    for name, vm in local.selected_vms : name => merge(vm, {
      machine_type = lookup(
        lookup(var.config.sizes, vm.machine_type, {}),
        local.cloud,
        null,
      )

      image = try(
        var.config.images[vm.image][local.cloud].image,
        null,
      )

      boot_disk = merge(vm.boot_disk, {
        type = lookup(
          lookup(var.config.disk_types, vm.boot_disk.type, {}),
          local.cloud,
          null,
        )
      })
    })
  }

  bastion_vm = try(
    one([for vm in values(local.vms) : vm if vm.role == "bastion"]),
    null,
  )

  workload_vms = {
    for name, vm in local.vms : name => vm
    if vm.role != "bastion"
  }

  #PPP
  subnet_by_role = local.enabled ? {
    bastion  = module.network[0].management_subnet_id
    ui       = module.network[0].management_subnet_id
    database = module.network[0].workload_subnet_id
    history  = module.network[0].workload_subnet_id
    fetcher  = module.network[0].workload_subnet_id
  } : {}
}