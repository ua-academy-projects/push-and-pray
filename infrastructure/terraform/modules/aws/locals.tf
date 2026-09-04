locals {
  cloud = "aws"

  selected_vms = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == local.cloud
  }

  subnet_class_by_role = {
    bastion  = "management"
    database = "workload"
    history  = "workload"
    fetcher  = "workload"
    ui       = "workload"
  }

  subnet_id_by_class = local.enabled ? {
    management = module.network[0].management_subnet_id
    workload   = module.network[0].workload_subnet_id
  } : {}

  enabled = length(local.selected_vms) > 0

  region = lookup(
    lookup(var.config.regions, var.config.location, {}),
    local.cloud,
    null,
  )
  zone = local.enabled ? sort(data.aws_availability_zones.available[0].names)[0] : null

  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  common_tags = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
      cloud       = local.cloud
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
        var.config.images[vm.image][local.cloud],
        null,
      )

      boot_disk = merge(vm.boot_disk, {
        type = lookup(
          lookup(var.config.disk_types, vm.boot_disk.type, {}),
          local.cloud,
          null,
        )
      })

      tags = merge(
        local.common_tags,
        try(vm.labels, {}),
        {
          Name = "${local.resource_prefix}-${name}"
          role = vm.role
        },
      )
    })
  }

  all_secret_ids = toset(flatten([
    for vm in values(local.vms) :
    values(vm.secret_mappings)
  ]))

  secret_ids_by_vm = {
    for name, vm in local.vms :
    name => toset(values(vm.secret_mappings))
  }

  vms_with_secrets = {
    for name, secret_ids in local.secret_ids_by_vm :
    name => secret_ids
    if length(secret_ids) > 0
  }
}