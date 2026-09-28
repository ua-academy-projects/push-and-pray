locals {
  location_suffixes = {
    for location in keys(local.locations) :
    location => location == var.config.default_location ? "" : "-${location}"
  }

  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  network_tags = {
    for location, vms in local.vms_by_location : location => {
      for role in distinct([for vm in values(vms) : vm.role]) : role => "${local.resource_prefix}-${role}"
    }
  }
}
