locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  enabled         = try(var.config.deployment_mode, "compose") == "k3s" && var.config.default_cloud == "gcp"
  location        = var.config.default_location
  placement       = local.enabled ? var.config.locations[local.location].gcp : null

  nodes = {
    for name, vm in var.config.vms : name => vm
    if local.enabled
    && lookup(vm, "cloud", var.config.default_cloud) == "gcp"
    && (contains(vm.tags, "k3s-server") || contains(vm.tags, "k3s-agent"))
  }

  servers = {
    for name, vm in local.nodes : name => vm
    if contains(vm.tags, "k3s-server")
  }

  agents = {
    for name, vm in local.nodes : name => vm
    if contains(vm.tags, "k3s-agent")
  }

  labels = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )
}
