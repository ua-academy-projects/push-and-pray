locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  tags = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )

  vms = {
    for name, vm in var.config.vms : name => merge(vm, {
      location = lookup(vm, "location", var.config.default_location)
    })
    if lookup(vm, "cloud", var.config.default_cloud) == "azure"
  }

  bastions = lookup(var.config.bastion, "cloud", var.config.default_cloud) == "azure" ? {
    (lookup(var.config.bastion, "location", var.config.default_location)) = merge(var.config.bastion, {
      location = lookup(var.config.bastion, "location", var.config.default_location)
    })
  } : {}

  functional_tags = {
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
          region   = var.networks[location].region
        }
      ]
    ]) : pair.key => pair
  }

  workload_ssh_rules = {
    for tag in values(local.functional_tags) : tag.key => merge(tag, {
      bastion_ip = local.bastions[tag.location].internal_ip
    })
    if tag.tag != "bastion" && contains(keys(local.bastions), tag.location)
  }

  ui_rules = {
    for tag in values(local.functional_tags) : tag.key => tag if tag.tag == "ui"
  }

  history_rules = {
    for location in keys(var.networks) : location => {
      region      = var.networks[location].region
      source_ip   = one([for vm in values(local.vms) : vm.internal_ip if vm.location == location && contains(vm.tags, "ui")])
      destination = "history"
    }
    if anytrue([for vm in values(local.vms) : vm.location == location && contains(vm.tags, "history")]) &&
    anytrue([for vm in values(local.vms) : vm.location == location && contains(vm.tags, "ui")])
  }

  postgresql_rules = {
    for location in keys(var.networks) : location => {
      region = var.networks[location].region
      source_ips = [
        for vm in values(local.vms) : vm.internal_ip
        if vm.location == location && anytrue([for tag in ["fetcher", "history", "ui"] : contains(vm.tags, tag)])
      ]
    }
    if var.config.database.mode == "self_managed" &&
    anytrue([for vm in values(local.vms) : vm.location == location && contains(vm.tags, "infrastructure")]) &&
    anytrue([
      for vm in values(local.vms) : vm.location == location &&
      anytrue([for tag in ["fetcher", "history", "ui"] : contains(vm.tags, tag)])
    ])
  }
}
