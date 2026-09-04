locals {
  resource_prefix = "${var.name_prefix}-${var.environment}"

  network_tags = {
    bastion = "${local.resource_prefix}-bastion"
    infra   = "${local.resource_prefix}-infra"
    history = "${local.resource_prefix}-history"
    fetcher = "${local.resource_prefix}-fetcher"
    ui      = "${local.resource_prefix}-ui"
  }
}
