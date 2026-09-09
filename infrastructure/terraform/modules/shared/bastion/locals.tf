locals {
  bastion = var.config.bastion

  vm = {
    role             = "bastion"
    size             = local.bastion.size
    image            = local.bastion.image
    internal_ip      = cidrhost(var.profile.subnets.management, var.host_index)
    assign_public_ip = true
    boot_disk = {
      size_gb = local.bastion.boot_disk.size_gb
      type    = local.bastion.boot_disk.type
    }
  }
}
