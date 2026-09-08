locals {
  vm_names = {
    for name, vm in var.vms :
    name => "${var.resource_prefix}-${name}"
  }

  subnet_ids_by_vm = {
    for name, vm in var.vms :
    name => vm.role == "bastion" ? var.management_subnet_id : var.workload_subnet_id
  }

  network_tags_by_vm = {
    for name, vm in var.vms :
    name => [for tag in vm.network_tags : "${var.resource_prefix}-${tag}"]
  }

  labels_by_vm = {
    for name, vm in var.vms :
    name => merge(
      vm.labels,
      var.common_labels,
      {
        role  = vm.role
        cloud = vm.effective_cloud
      },
    )
  }
}
