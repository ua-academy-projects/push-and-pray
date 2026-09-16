locals {
  project_config = jsondecode(file(var.project_config_path))

  config = merge(local.project_config, {
    vms = merge(local.project_config.vms, {
      bastion = merge(
        local.project_config.vm_defaults,
        {
          cloud         = local.project_config.default_cloud
          location      = local.project_config.default_location
          internal_ip   = cidrhost(local.project_config.network.management_subnet_cidr, 4)
          ssh_port      = 22
          allowed_cidrs = ["0.0.0.0/0"]
        },
        try(local.project_config.vms.bastion, {}),
        { role = "bastion", assign_public_ip = true },
      )
    })
  })
}
