locals {
  prefix = var.name_prefix

  # Network tags are the handle firewall rules use to select instances.
  # Nothing is reachable unless it carries the right tag.
  tag_bastion = "${local.prefix}-bastion"

  # "user:public-key" lines, one per person. Empty when OS Login is enabled.
  ssh_keys_metadata = join("\n", [
    for user, key in var.ssh_users : "${user}:${trimspace(key)}"
  ])

  # Common metadata for every instance in this module.
  # Built as one map with nulls filtered out, so the type is always map(string).
  common_metadata = {
    for k, v in {
      # Project-wide SSH keys are ignored: access is decided here, not by whoever
      # happens to have project metadata permissions.
      block-project-ssh-keys = "TRUE"
      enable-oslogin         = "FALSE"
      serial-port-enable = "FALSE"
      ssh-keys           = local.ssh_keys_metadata
    } : k => v if v != null
  }

  startup_script = templatefile("${path.module}/templates/sshd-hardening.sh.tftpl", {
    ssh_port = var.ssh_port
  })

  labels = merge(
    {
      managed-by = "terraform"
      module     = "network-bastion"
    },
    var.labels
  )
}