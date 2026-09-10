locals {
  vms = {
    for name, vm in var.config.vms : name => merge(
      { assign_public_ip = false, disks = [] },
      var.config.vm_defaults,
      vm,
      {
        disks = [
          for disk in try(vm.disks, []) : merge({ type = "standard" }, disk)
        ]
      },
    )
    if try(vm.cloud, var.config.default_cloud) == "aws" && contains(keys(var.workload_subnet_ids), vm.location)
  }

  key_pair_locations = {
    for location in keys(var.workload_subnet_ids) :
    location => var.config.locations[location].aws
  }
}
