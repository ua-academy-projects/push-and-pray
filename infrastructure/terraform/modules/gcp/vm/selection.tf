locals {
  vms = {
    for name, vm in var.config.vms : name => merge({ assign_public_ip = false }, var.config.vm_defaults, vm)
    if try(vm.cloud, var.config.default_cloud) == "gcp" && contains(keys(var.workload_subnet_ids), vm.location)
  }
}
