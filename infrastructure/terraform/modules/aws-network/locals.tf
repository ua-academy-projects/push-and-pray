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

  placements = {
    for location in toset([
      for vm in values(var.config.vms) : lookup(vm, "location", var.config.default_location)
      if lookup(vm, "cloud", var.config.default_cloud) == "aws"
    ]) :
    location => var.config.locations[location].aws
  }

  managed_database_placements = var.config.database.mode == "managed" && var.config.default_cloud == "aws" ? {
    (var.config.default_location) = var.config.locations[var.config.default_location].aws
  } : {}

  database_subnets = {
    for subnet in flatten([
      for location, placement in local.managed_database_placements : [
        for index, cidr in var.config.network.managed_database.aws_private_subnet_cidrs : {
          key      = "${location}/${index}"
          location = location
          region   = placement.region
          cidr     = cidr
          zone = index == 0 ? placement.zone : [
            for zone in data.aws_availability_zones.available[location].names : zone
            if zone != placement.zone
          ][0]
        }
      ]
    ]) : subnet.key => subnet
  }
}
