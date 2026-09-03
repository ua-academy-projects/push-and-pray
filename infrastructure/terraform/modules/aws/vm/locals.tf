locals {

  instance_tags_by_vm = {
    for name, vm in var.vms :
    name => merge(
      lookup(vm, "labels", {}),
      var.common_labels,
      {
        Name  = "${var.resource_prefix}-${name}"
        role  = vm.role
        cloud = vm.effective_cloud
      },
    )
  }
  subnet_ids_by_vm = {
    for name, vm in var.vms :
    name => vm.role == "bastion"
    ? var.management_subnet_id
    : var.workload_subnet_id
  }

  vm_names = {
    for name, vm in var.vms :
    name => "${var.resource_prefix}-${name}"
  }
}
