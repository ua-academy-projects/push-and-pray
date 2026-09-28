locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  common_tags = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )
  admin_username = sort(keys(var.config.ssh_users))[0]
  location       = lookup(var.config.bastion, "location", var.config.default_location)

  bastions = lookup(var.config.bastion, "cloud", var.config.default_cloud) == "azure" ? {
    bastion = merge(var.config.bastion, {
      location                  = local.location
      resource_name             = "${local.resource_prefix}-bastion"
      region                    = var.config.locations[local.location].azure.region
      zone                      = try(var.config.locations[local.location].azure.zone, null)
      machine_type              = var.config.machine_types[var.config.bastion.machine_type].azure
      image                     = var.config.images[var.config.bastion.image].azure
      subnet_id                 = var.networks[local.location].public_subnet_id
      network_security_group_id = var.network_security_group_ids[local.location].bastion
      assign_public_ip          = true
      identity_id               = var.identity_ids.bastion
      admin_username            = local.admin_username
      ssh_public_key            = var.config.ssh_users[local.admin_username]
      data_disks                = {}
      cloud_init = templatefile(
        "${path.root}/templates/bastion-cloud-config.yaml.tftpl",
        { ssh_port = var.config.bastion.ssh_port },
      )
      tags = merge(local.common_tags, try(var.config.bastion.labels, {}), {
        Name           = "${local.resource_prefix}-bastion"
        FunctionalTags = "bastion"
      })
      boot_disk = merge(var.config.bastion.boot_disk, {
        type = var.config.disk_types[var.config.bastion.boot_disk.disk_type].azure.type
      })
    })
  } : {}
}
