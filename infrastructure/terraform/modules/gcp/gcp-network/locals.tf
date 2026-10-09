locals {
  cloud_name      = "gcp"
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  cloud_config    = lookup(var.config.clouds, local.cloud_name, {})
  network         = merge(var.config.network, lookup(local.cloud_config, "network", {}))
  vms = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == local.cloud_name
  }
}
