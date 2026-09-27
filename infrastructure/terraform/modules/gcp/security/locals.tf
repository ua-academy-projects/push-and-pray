locals {
  network_tags = {
    bastion    = "${var.resource_prefix}-bastion"
    infra      = "${var.resource_prefix}-infra"
    history    = "${var.resource_prefix}-history"
    fetcher    = "${var.resource_prefix}-fetcher"
    ui         = "${var.resource_prefix}-ui"
    k3s_server = "${var.resource_prefix}-k3s-server"
    k3s_agent  = "${var.resource_prefix}-k3s-agent"
  }
}
