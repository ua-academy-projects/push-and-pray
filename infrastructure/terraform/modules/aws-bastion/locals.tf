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

  bastions = lookup(var.config.bastion, "cloud", var.config.default_cloud) == "aws" ? {
    bastion = merge(var.config.bastion, {
      location           = local.location
      region             = var.config.locations[local.location].aws.region
      machine_type       = var.config.machine_types[var.config.bastion.machine_type].aws
      image              = var.config.images[var.config.bastion.image].aws
      labels             = merge(local.context.labels, try(var.config.bastion.labels, {}))
      resource_name      = "${local.context.resource_prefix}-bastion"
      subnet_id          = var.networks[local.location].public_subnet_id
      security_group_ids = [var.security_group_ids[local.location].bastion]
      instance_profile   = null
      key_name           = var.bootstrap_key_names[local.location]
      assign_public_ip   = true
      tags               = ["bastion"]
      data_disks         = {}
      cloud_init = templatefile(
        "${path.root}/templates/bastion-cloud-config.yaml.tftpl",
        { ssh_port = var.config.bastion.ssh_port },
      )
      boot_disk = merge(var.config.bastion.boot_disk, {
        type = var.config.disk_types[var.config.bastion.boot_disk.disk_type].aws.type
        iops = try(
          var.config.bastion.boot_disk.iops,
          var.config.disk_types[var.config.bastion.boot_disk.disk_type].aws.iops,
          null,
        )
      })
    })
  } : {}
}
