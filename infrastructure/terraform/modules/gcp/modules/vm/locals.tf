locals {
  machine_type   = var.profile.machine_sizes[var.vm.size]
  image          = var.profile.images[var.vm.image]
  boot_disk_type = var.profile.disk_types[var.vm.boot_disk.type]
}
