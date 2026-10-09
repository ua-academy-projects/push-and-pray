locals {
  aws_vms = var.config.default_cloud == "aws" && !try(var.config.managed_kubernetes, false) ? {
    for name, vm in try(var.config.vms, {}) : name => merge(vm, {
      native_vm_type   = var.config.size_map[vm.size].aws
      native_disk_type = var.config.disk_type_map[vm.disk_type].aws
      native_image     = var.config.image_map[vm.image].aws
    })
  } : {}
}
