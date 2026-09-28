locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  locations = toset(concat(
    [
      for vm in values(var.config.vms) : lookup(vm, "location", var.config.default_location)
      if lookup(vm, "cloud", var.config.default_cloud) == "azure"
    ],
    lookup(var.config.bastion, "cloud", var.config.default_cloud) == "azure" ?
    [lookup(var.config.bastion, "location", var.config.default_location)] : [],
    var.config.database.mode == "managed" && var.config.default_cloud == "azure" ?
    [var.config.default_location] : [],
  ))

  resource_groups = length(local.locations) > 0 ? {
    main = var.config.locations[sort(tolist(local.locations))[0]].azure.region
  } : {}

  tags = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )
}
