locals {
  vms = var.vms

  data_disks = {
    for disk in flatten([
      for vm_name, vm in local.vms : [
        for disk_name, disk in vm.data_disks : merge(disk, {
          key       = "${vm_name}/${disk_name}"
          name      = "${vm.resource_name}-${disk_name}"
          disk_name = disk_name
          vm_name   = vm_name
          zone      = vm.zone
          labels    = vm.labels
        })
      ]
    ]) : disk.key => disk
  }
}
