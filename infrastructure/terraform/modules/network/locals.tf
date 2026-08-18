locals {
  prefix = var.name_prefix

  # Network tags are the handle firewall rules use to select instances.
  # Nothing is reachable unless it carries the right tag.
  tag_bastion = "${local.prefix}-bastion"
  tag_infra   = "${local.prefix}-infra"
  tag_history = "${local.prefix}-history"
  tag_fetcher = "${local.prefix}-fetcher"
  tag_ui      = "${local.prefix}-ui"

  workload_tags = [
    local.tag_infra,
    local.tag_history,
    local.tag_fetcher,
    local.tag_ui,
  ]

  internal_ranges = compact([
    var.management_subnet_cidr,
    var.workload_subnet_cidr,
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
