locals {
  enabled = anytrue([
    for vm in values(var.config.vms) : try(vm.cloud, var.config.default_cloud) == "gcp"
  ])

  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  network_tags = {
    bastion = "${local.resource_prefix}-bastion"
    infra   = "${local.resource_prefix}-infra"
    history = "${local.resource_prefix}-history"
    fetcher = "${local.resource_prefix}-fetcher"
    ui      = "${local.resource_prefix}-ui"
  }

  ui_public_ports = [
    for port in var.config.network.ui_public_ports : tostring(port)
  ]

  # A fresh bastion listens on 22 until Ansible installs the final sshd policy;
  # there is no config field for this yet, so the bootstrap firewall rule stays disabled.
  enable_bastion_ssh_bootstrap = false
}
