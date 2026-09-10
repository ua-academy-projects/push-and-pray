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
    if try(vm.cloud, var.config.default_cloud) == "gcp" && contains(keys(var.workload_subnet_ids), vm.location)
  }

  data_disks = {
    for disk in flatten([
      for vm_name, vm in local.vms : [
        for disk_index, disk in vm.disks : {
          key        = "${vm_name}-data-${disk_index + 1}"
          vm_name    = vm_name
          disk_index = disk_index
          disk_type  = disk.type
          disk_size  = disk.size
          location   = vm.location
        }
      ]
    ]) : disk.key => disk
  }
}
