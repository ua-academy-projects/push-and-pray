locals {
  bastion_vm = var.vms.bastion

  network_tags = {
    for name, vm in var.vms : vm.role => "${var.resource_prefix}-${name}"
  }
}
