locals {
  resource_prefix     = "${var.config.name_prefix}-${var.config.environment}"
  ui_public_ports_str = [for port in var.config.network.ui_public_ports : tostring(port)]

  selected_vms = var.selected_vms

  bastion = try(local.selected_vms.bastion, null)

  bastion_ssh_ports = local.bastion == null ? [] : distinct([
    tostring(local.bastion.ssh_port),
    "22",
  ])

  tag_present = {
    for tag in ["infra", "history", "fetcher", "ui", "k3s_server", "k3s_agent"] :
    tag => anytrue([for vm in local.selected_vms : contains(vm.roles, tag)])
  }

  # Bastion may SSH to every workload role, including k3s nodes.
  workload_target_tags = [
    for role in ["infra", "history", "fetcher", "ui", "k3s_server", "k3s_agent"] : var.network_tags[role]
    if local.tag_present[role]
  ]

  # Tags of the k3s nodes present, used for the intra-cluster firewall rule.
  k3s_present = local.tag_present["k3s_server"] || local.tag_present["k3s_agent"]
  k3s_tags = [
    for role in ["k3s_server", "k3s_agent"] : var.network_tags[role]
    if local.tag_present[role]
  ]
}
