locals {
  vm_size        = var.profile.machine_sizes[var.vm.size]
  boot_disk_type = var.profile.disk_types[var.vm.boot_disk.type]

  # publisher:offer:sku:version, the way the Marketplace and az name an image.
  image = zipmap(["publisher", "offer", "sku", "version"], split(":", var.profile.images[var.vm.image]))

  # A disk cannot be smaller than the image it is created from, and the
  # Ubuntu images are 30 GiB - larger than the 10 GiB the other clouds boot
  # from. The configured size is kept wherever it is larger.
  boot_disk_size_gb = max(var.vm.boot_disk.size_gb, var.minimum_boot_disk_size_gb)

  # Azure provisions one administrator on its own and insists on it; the
  # first user takes that place, and cloud-init creates every user, that one
  # included, the same way it does on AWS.
  admin_username = sort(keys(var.ssh_users))[0]
}

locals {
  custom_data = "#cloud-config\n${yamlencode({
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
