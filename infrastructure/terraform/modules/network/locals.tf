locals {
  prefix = var.name_prefix

  # Network tags are the handle firewall rules use to select instances.
  # Nothing is reachable unless it carries the right tag.
  tag_bastion = "${local.prefix}-bastion"
  tag_app     = "${local.prefix}-app"
  tag_db      = "${local.prefix}-db"

  # "user:public-key" lines, one per person. Empty when OS Login is enabled.
  ssh_keys_metadata = join("\n", [
    for user, key in var.ssh_users : "${user}:${trimspace(key)}"
  ])

  use_metadata_keys = !var.enable_os_login && length(var.ssh_users) > 0

  # Common metadata for every instance in this module.
  # Built as one map with nulls filtered out, so the type is always map(string).
  common_metadata = {
    for k, v in {
      # Project-wide SSH keys are ignored: access is decided here, not by whoever
      # happens to have project metadata permissions.
      block-project-ssh-keys = var.enable_os_login ? "FALSE" : "TRUE"
      enable-oslogin         = var.enable_os_login ? "TRUE" : "FALSE"
      serial-port-enable = "FALSE"
      ssh-keys           = local.use_metadata_keys ? local.ssh_keys_metadata : null
    } : k => v if v != null
  }

  startup_script = templatefile("${path.module}/templates/sshd-hardening.sh.tftpl", {
    ssh_port = var.ssh_port
  })

  internal_ranges = compact([
    var.public_subnet_cidr,
    var.private_subnet_cidr,
  ])

  firewall_log_config      = var.enable_firewall_logging ? [1] : []
  firewall_deny_log_config = var.log_denied_traffic ? [1] : []

  labels = merge(
    {
      managed-by = "terraform"
      module     = "network-bastion"
    },
    var.labels
  )
}
