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

  vms = {
    for name, vm in var.config.vms : name => merge(vm, {
      location = lookup(vm, "location", var.config.default_location)
    })
    if lookup(vm, "cloud", var.config.default_cloud) == "aws"
  }

  bastions = lookup(var.config.bastion, "cloud", var.config.default_cloud) == "aws" ? {
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
          region   = var.networks[location].region
        }
      ]
    ]) : pair.key => pair
  }

  bastion_ssh_rules = {
    for rule in flatten([
      for location, vm in local.bastions : [
        for index, cidr in vm.allowed_cidrs : {
          key      = "${location}/${index}/${vm.ssh_port}"
          location = location
          cidr     = cidr
          port     = vm.ssh_port
        }
      ]
    ]) : rule.key => rule
  }

  workload_ssh_rules = {
    for tag in values(local.tags) : tag.key => tag
    if tag.tag != "bastion" && contains(keys(local.bastions), tag.location)
  }

  ui_rules = {
    for rule in flatten([
      for tag in values(local.tags) : [
        for port in var.config.network.ui_public_ports : {
          key     = "${tag.key}/${port}"
          tag_key = tag.key
          region  = tag.region
          port    = port
        }
      ] if tag.tag == "ui"
    ]) : rule.key => rule
  }

  history_rules = {
    for location in keys(var.networks) : location => {
      region = var.networks[location].region
    }
    if contains(keys(local.tags), "${location}/history") && contains(keys(local.tags), "${location}/ui")
  }

  postgresql_rules = {
    for client in flatten([
      for location in keys(var.networks) : [
        for tag in ["fetcher", "history", "ui"] : {
          key      = "${location}/${tag}"
          location = location
          tag      = tag
          region   = var.networks[location].region
        }
        if contains(keys(local.tags), "${location}/${tag}")
      ] if contains(keys(local.tags), "${location}/infrastructure") && var.config.database.mode == "self_managed"
    ]) : client.key => client
  }

  rabbitmq_rules = {
    for tag in ["fetcher", "history"] : "${var.config.default_location}/${tag}" => {
      location = var.config.default_location
      tag      = tag
      region   = var.networks[var.config.default_location].region
    }
    if var.config.database.mode == "managed" && var.config.default_cloud == "aws" &&
    contains(keys(local.tags), "${var.config.default_location}/infrastructure") &&
    contains(keys(local.tags), "${var.config.default_location}/${tag}")
  }

  redis_rules = {
    for tag in ["ui"] : "${var.config.default_location}/${tag}" => {
      location = var.config.default_location
      tag      = tag
      region   = var.networks[var.config.default_location].region
    }
    if var.config.database.mode == "managed" && var.config.default_cloud == "aws" &&
    contains(keys(local.tags), "${var.config.default_location}/infrastructure") &&
    contains(keys(local.tags), "${var.config.default_location}/${tag}")
  }
}
