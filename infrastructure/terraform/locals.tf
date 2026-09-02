locals {
  config = jsondecode(file(var.project_config_path))

  configured_vms = {
    for name, vm in local.config.vms : name => merge(vm, {
      cloud = try(vm.cloud, local.config.default_cloud)
    })
  }

  gcp_vms = {
    for name, vm in local.configured_vms : name => vm
    if vm.cloud == "gcp"
  }

  aws_vms = {
    for name, vm in local.configured_vms : name => vm
    if vm.cloud == "aws"
  }

  enabled_clouds = toset([
    for vm in values(local.configured_vms) : vm.cloud
  ])

  workload_vms = {
    for name, vm in local.configured_vms : name => vm
    if vm.role != "bastion"
  }

  default_location = values(local.config.locations)[0]
  resource_prefix  = "${local.config.name_prefix}-${local.config.environment}"
}
