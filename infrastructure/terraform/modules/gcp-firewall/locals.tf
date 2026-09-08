locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  vms = {
    for name, vm in var.config.vms : name => merge(vm, {
      location      = lookup(vm, "location", var.config.default_location)
      ssh_port      = lookup(vm, "ssh_port", 22)
      allowed_cidrs = lookup(vm, "allowed_cidrs", [])
    })
    if lookup(vm, "cloud", var.config.default_cloud) == "gcp"
  }

  tags = {
    for pair in flatten([
      for location in keys(var.networks) : [
        for tag in toset(flatten([
          for vm in values(local.vms) : vm.tags if vm.location == location
          ])) : {
          key      = "${location}/${tag}"
          location = location
          tag      = tag
        }
      ]
    ]) : pair.key => pair
  }

  bastions = {
    for name, vm in local.vms : vm.location => vm
    if contains(vm.tags, "bastion")
  }

  workload_locations = toset([
    for tag in values(local.tags) : tag.location if tag.tag != "bastion"
  ])

  history_locations = toset([
    for location in keys(var.networks) : location
    if contains(keys(local.tags), "${location}/history") && contains(keys(local.tags), "${location}/ui")
  ])

  database_locations = toset([
    for location in keys(var.networks) : location
    if contains(keys(local.tags), "${location}/database") && anytrue([
      for tag in ["fetcher", "history", "ui"] :
      contains(keys(local.tags), "${location}/${tag}")
    ])
  ])
}
