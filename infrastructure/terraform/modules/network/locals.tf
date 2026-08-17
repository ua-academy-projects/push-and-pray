locals {
  prefix = var.name_prefix

  # Network tags are the handle firewall rules use to select instances.
  # Nothing is reachable unless it carries the right tag.
  tag_bastion = "${local.prefix}-bastion"
  tag_app     = "${local.prefix}-app"
  tag_db      = "${local.prefix}-db"

  # Placeholder contract for the public-facing UI instance, which is created
  # elsewhere (issue #14). The rule exists now; whoever builds that instance only
  # has to attach this tag - exported through the network_tags output.
  tag_ui = "${local.prefix}-ui"

  internal_ranges = compact([
    var.public_subnet_cidr,
    var.private_subnet_cidr,
  ])

  firewall_log_config      = var.enable_firewall_logging ? [1] : []
  firewall_deny_log_config = var.log_denied_traffic ? [1] : []

  labels = merge(
    {
      managed_by = "terraform"
      module     = "network"
    },
    var.labels
  )
}
