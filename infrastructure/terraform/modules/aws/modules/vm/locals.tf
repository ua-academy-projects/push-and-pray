locals {
  instance_type  = var.profile.machine_sizes[var.vm.size]
  ami            = var.profile.images[var.vm.image]
  boot_disk_type = var.profile.disk_types[var.vm.boot_disk.type]
}

locals {
  user_data = "#cloud-config\n${yamlencode({
    users = [
      for username, public_key in var.ssh_users : {
        name                = username
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        shell               = "/bin/bash"
        ssh_authorized_keys = [trimspace(public_key)]
      }
    ]
  })}"
}
