locals {
  bastion_vm = var.vms.bastion

  vm_names_by_role = {
    for name, vm in var.vms : vm.role => name
  }
}
