locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  ui_public_ports_str = [for port in var.config.network.ui_public_ports : tostring(port)]

  selected_vms = var.selected_vms

  bastion = try(local.selected_vms.bastion, null)

  tailscale_ports = try(var.config.tailscale.enabled, false) ? [for p in try(var.config.tailscale.allowed_ports, []) : tostring(p)] : []

  bastion_ssh_rules = local.bastion == null ? {} : {
    for pair in setproduct(
      local.bastion.allowed_cidrs,
      distinct([local.bastion.ssh_port, 22])
      ) : "${pair[0]}-${pair[1]}" => {
      cidr = pair[0]
      port = pair[1]
    }
  }

  tag_present = {
    for tag in ["infra", "history", "fetcher", "ui", "k3s_server", "k3s_agent"] :
    tag => anytrue([for vm in local.selected_vms : contains(vm.roles, tag)])
  }

  workload_tags_present = [
    for role in ["infra", "history", "fetcher", "ui", "k3s_server", "k3s_agent"] : role
    if local.tag_present[role]
  ]

  # k3s nodes present on this cloud (drives the intra-cluster rules below).
  k3s_present = local.tag_present["k3s_server"] || local.tag_present["k3s_agent"]
}
