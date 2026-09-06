locals {
  # Firewall rules and for_each keys take strings; the configuration holds numbers.
  ui_public_ports = [for port in var.config.network.ui_public_ports : tostring(port)]

  network_tags = {
    bastion = "${var.resource_prefix}-bastion"
    infra   = "${var.resource_prefix}-infra"
    history = "${var.resource_prefix}-history"
    fetcher = "${var.resource_prefix}-fetcher"
    ui      = "${var.resource_prefix}-ui"
  }
}
