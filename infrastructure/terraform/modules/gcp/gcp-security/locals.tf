locals {
  cloud_name      = "gcp"
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  vms = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == local.cloud_name
  }
  network_tags = {
    for role in [
      "bastion",
      "infra",
      "history",
      "fetcher",
      "ui",
      "k3s",
      "k3s-server",
      "k3s-agent",
      "k3s-ingress",
    ] : role => "${local.resource_prefix}-${role}"
  }
  bastion     = lookup(local.vms, "bastion", {})
  k3s_nodes   = { for name, vm in local.vms : name => vm if vm.role == "k3s" }
  k3s_servers = { for name, vm in local.k3s_nodes : name => vm if vm.k3s_role == "server" }
}
