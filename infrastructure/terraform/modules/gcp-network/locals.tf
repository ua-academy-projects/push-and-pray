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
      if lookup(vm, "cloud", var.config.default_cloud) == "gcp"
    ]) :
    location => var.config.locations[location].gcp
  }
}
