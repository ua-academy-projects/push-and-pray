locals {
  context = {
    resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
    labels = merge(
      {
        application = var.config.name_prefix
        environment = var.config.environment
        managed_by  = "terraform"
      },
      var.config.common_labels,
    )
  }

  location = lookup(var.config.bastion, "location", var.config.default_location)
  cloud_init = templatefile(
    "${path.root}/templates/bastion-cloud-config.yaml.tftpl",
    { ssh_port = var.config.bastion.ssh_port },
  )

  bastions = lookup(var.config.bastion, "cloud", var.config.default_cloud) == "gcp" ? {
    bastion = merge(var.config.bastion, {
      location              = local.location
      region                = var.config.locations[local.location].gcp.region
      zone                  = var.config.locations[local.location].gcp.zone
      machine_type          = var.config.machine_types[var.config.bastion.machine_type].gcp
      image                 = var.config.images[var.config.bastion.image].gcp
      labels                = merge(local.context.labels, try(var.config.bastion.labels, {}))
      resource_name         = "${local.context.resource_prefix}-bastion"
      subnet_id             = var.networks[local.location].public_subnet_id
      assign_public_ip      = true
      provider_tags         = ["${local.context.resource_prefix}-${local.location}-bastion"]
      service_account_email = null
      data_disks            = {}
      cloud_init            = local.cloud_init
      boot_disk = merge(var.config.bastion.boot_disk, {
        type = var.config.disk_types[var.config.bastion.boot_disk.disk_type].gcp.type
        iops = try(
          var.config.bastion.boot_disk.iops,
          var.config.disk_types[var.config.bastion.boot_disk.disk_type].gcp.iops,
          null,
        )
      })
      metadata = {
        "enable-oslogin" = "FALSE"
        "ssh-keys" = join("\n", [
          for username, public_key in var.config.ssh_users :
          "${username}:${trimspace(public_key)}"
        ])
        "user-data" = local.cloud_init
      }
    })
  } : {}
}
