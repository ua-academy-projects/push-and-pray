locals {
  bastion = var.config.bastion

  vm = {
    role             = "bastion"
    size             = local.bastion.size
    image            = local.bastion.image
    internal_ip      = cidrhost(var.profile.subnets.management, var.host_index)
    assign_public_ip = true
    # The bastion is the subnet router: it forwards packets addressed to the
    # other clouds and to the tailnet, which every cloud drops by default.
    ip_forwarding = true
    boot_disk = {
      size_gb = local.bastion.boot_disk.size_gb
      type    = local.bastion.boot_disk.type
    }
  }
}
