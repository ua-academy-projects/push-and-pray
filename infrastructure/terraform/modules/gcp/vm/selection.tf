locals {
  vms = {
    for name, vm in var.config.vms : name => merge({ assign_public_ip = false, disks = 1 }, var.config.vm_defaults, vm)
    if try(vm.cloud, var.config.default_cloud) == "gcp" && contains(keys(var.workload_subnet_ids), vm.location)
  }

  data_disks = {
    for disk in flatten([
      for vm_name, vm in local.vms : [
        for disk_index in range(1, vm.disks) : {
          key        = "${vm_name}-data-${disk_index}"
          vm_name    = vm_name
          disk_index = disk_index
          disk_type  = vm.disk_type
          disk_size  = try(vm.disk_size, var.config.vm_defaults.data_disk_size_gb)
          location   = vm.location
        }
      ]
    ]) : disk.key => disk
  }
}
