locals {
  config = jsondecode(file(var.project_config_path))

  default_provider_locations = {
    gcp = values(local.config.locations)[0].gcp
    aws = values(local.config.locations)[0].aws
  }

  configured_vms = {
    for name, vm in local.config.vms : name => merge(local.config.vm_defaults, vm, {
      cloud = try(vm.cloud, local.config.default_cloud)
    })
  }

  resolved_vms = {
    for name, vm in local.configured_vms : name => merge(vm, {
      size_config          = local.config.sizes[vm.size]
      instance_type_config = local.config.provider_mappings.instance_types[vm.size][vm.cloud]
      provider_disk_type   = local.config.provider_mappings.disk_types[vm.disk_type][vm.cloud]
      provider_image       = local.config.provider_mappings.images[vm.image][vm.cloud]
      location_config      = local.config.locations[vm.location][vm.cloud]
    })
  }

  gcp_vms = {
    for name, vm in local.resolved_vms : name => vm
    if vm.cloud == "gcp"
  }

  aws_vms = {
    for name, vm in local.resolved_vms : name => vm
    if vm.cloud == "aws"
  }

  enabled_clouds = toset([
    for vm in values(local.resolved_vms) : vm.cloud
  ])

  bastion_vm = local.resolved_vms.bastion
  workload_vms = {
    for name, vm in local.resolved_vms : name => vm
    if vm.role != "bastion"
  }

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  common_labels = merge(
    local.config.common_labels,
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
    },
  )

  common_tags = local.common_labels
}
