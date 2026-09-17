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
    for location in toset(concat(
      [
        for vm in values(var.config.vms) : lookup(vm, "location", var.config.default_location)
        if lookup(vm, "cloud", var.config.default_cloud) == "gcp"
      ],
      lookup(var.config.bastion, "cloud", var.config.default_cloud) == "gcp" ?
      [lookup(var.config.bastion, "location", var.config.default_location)] : [],
    )) :
    location => var.config.locations[location].gcp
  }
}
