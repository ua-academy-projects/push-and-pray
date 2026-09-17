locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  vms = {
    for name, vm in var.config.vms : name => merge(vm, {
      location = lookup(vm, "location", var.config.default_location)
    })
    if lookup(vm, "cloud", var.config.default_cloud) == "gcp"
  }

  bastions = lookup(var.config.bastion, "cloud", var.config.default_cloud) == "gcp" ? {
    (lookup(var.config.bastion, "location", var.config.default_location)) = merge(var.config.bastion, {
      location = lookup(var.config.bastion, "location", var.config.default_location)
    })
  } : {}

  tags = {
    for pair in flatten([
      for location in keys(var.networks) : [
        for tag in setunion(
          toset(flatten([
            for vm in values(local.vms) : vm.tags if vm.location == location
          ])),
          contains(keys(local.bastions), location) ? toset(["bastion"]) : toset([]),
          ) : {
          key      = "${location}/${tag}"
          location = location
          tag      = tag
        }
      ]
    ]) : pair.key => pair
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
    if var.config.database.mode == "self_managed" && contains(keys(local.tags), "${location}/infrastructure") && anytrue([
      for tag in ["fetcher", "history", "ui"] :
      contains(keys(local.tags), "${location}/${tag}")
    ])
  ])

  managed_database_location = var.config.default_location
}
