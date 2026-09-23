locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  bastion = try([
    for vm in var.selected_vms : vm
    if contains(vm.roles, "bastion")
  ][0], null)

  bastion_ssh_ports = local.bastion == null ? [] : distinct([
    tostring(local.bastion.ssh_port),
    "22",
  ])
}
