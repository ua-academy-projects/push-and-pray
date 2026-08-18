locals {
  prefix = var.name_prefix

  # Network tags are the handle firewall rules use to select instances.
  # The tag comes from the network module; the local one is the same value and is
  # kept only so the module still names its instance correctly when used standalone.
  tag_bastion = "${local.prefix}-bastion"

  instance_tags = distinct(compact([local.tag_bastion, var.network_tag]))

  # "user:public-key" lines, one per person.
  ssh_keys_metadata = join("\n", [
    for user, key in var.ssh_users : "${user}:${trimspace(key)}"
  ])

  common_metadata = {
    # Project-wide SSH keys are ignored: access is decided here, not by whoever
    # happens to have project metadata permissions.
    block-project-ssh-keys = "TRUE"
    serial-port-enable     = "FALSE"
    ssh-keys               = local.ssh_keys_metadata
  }

  startup_script = templatefile("${path.module}/templates/sshd-hardening.sh.tftpl", {
    ssh_port = var.ssh_port
  })

  labels = merge(
    {
      managed_by = "terraform"
      module     = "bastion"
    },
    var.labels
  )
}
